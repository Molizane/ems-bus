-module(ems_oauth2_authorize).

-export([execute/1]).
-export([code_request/1]).

-include("include/ems_config.hrl").
-include("include/ems_schema.hrl").


execute(Request = #request{type = Type, 
						   protocol_bin = Protocol, 
						   port = Port, 
						   host = Host, 
						   user_agent = UserAgent, 
						   user_agent_version = UserAgentVersion,
						   service  = Service = #service{oauth2_allow_client_credentials = OAuth2AllowClientCredentials}}) -> 
	try
		case Type of
			<<"GET">> -> GrantType = ems_util:get_querystring(<<"response_type">>, <<>>, Request);
			<<"POST">> -> GrantType = ems_util:get_querystring(<<"grant_type">>, <<>>, Request);
			_ -> GrantType = undefined
		end,
		Result = case GrantType of
				<<"password">> -> 
					ems_db:inc_counter(ems_oauth2_grant_type_password),
					case ems_util:get_client_request_by_id_and_secret(Request) of
						{ok, Client0} ->	password_grant(Request, Client0);
						_ -> password_grant(Request, undefined) % cliente é opcional no grant_type password
					end;
				<<"client_credentials">> ->
					case ems_util:get_client_request_by_id_and_secret(Request) of
						{ok, Client0} ->
							case OAuth2AllowClientCredentials of
								true ->
									ems_db:inc_counter(ems_oauth2_grant_type_client_credentials),
									client_credentials_grant(Request, Client0);
								false ->
									ems_db:inc_counter(ems_oauth2_client_credentials_denied),
									{error, access_denied, eoauth2_client_credentials_denied}	
							end;
						Error -> Error
					end;
				<<"token">> -> 
					ems_db:inc_counter(ems_oauth2_grant_type_token),
					case ems_util:get_client_request_by_id(Request) of
						{ok, Client0} -> authorization_request(Request, Client0);
						Error -> Error
					end;
				<<"code">> ->	
					ems_db:inc_counter(ems_oauth2_grant_type_code),
					case ems_util:get_client_request_by_id(Request) of
						{ok, Client0} -> authorization_request(Request, Client0);	
						Error -> Error
					end;
				<<"authorization_code">> ->	
					ems_db:inc_counter(ems_oauth2_grant_type_authorization_code),
					case ems_util:get_client_request_by_id_and_secret(Request) of
						{ok, Client0} -> access_token_request(Request, Client0);
						Error -> Error
					end;
				<<"refresh_token">> ->	
					ems_db:inc_counter(ems_oauth2_grant_type_refresh_token),
					case ems_util:get_client_request_by_id(Request) of
						{ok, Client0} -> refresh_token_request(Request, Client0);	
						Error -> Error
					end;
				 _ -> 
					{error, access_denied, einvalid_grant_type}
		end, 
		case Result of
			{ok, [ {<<"access_token">>,AccessToken},
				   {<<"expires_in">>, ExpireIn},
				   {<<"resource_owner">>, User},
				   {<<"scope">>, Scope},
				   {<<"refresh_token">>, RefreshToken},
				   {<<"refresh_token_expires_in">>, RefreshTokenExpireIn},
				   {<<"token_type">>, TokenType}
				 ], 
				 Client
			 } ->
					% When it is authorization_code, we will record metrics for singlesignon
					case User =/= undefined of
						true -> 
							UserAgentBin = ems_util:user_agent_atom_to_binary(UserAgent),
							SingleSignonUserAgentMetricName = binary_to_atom(iolist_to_binary([<<"ems_oauth2_singlesignon_user_agent_">>, UserAgentBin, <<"_">>, UserAgentVersion]), utf8),
							ems_db:inc_counter(SingleSignonUserAgentMetricName),
							User2 = User;
						false -> 
							User2 = #user{}
					end,
					case Client =/= undefined of
						true ->
							ClientJson = ems_client:to_json(Client),
							ResourceOwner = ems_user:to_resource_owner(User, Client#client.id),
							ClientProp = [<<"\"client\":"/utf8>>, ClientJson, <<","/utf8>>],
							Client2 = Client;
						false ->
							ResourceOwner = ems_user:to_resource_owner(User),
							ClientProp = <<"\"client\": \"public\","/utf8>>,
							Client2 = #client{}
					end,
					ResponseData2 = iolist_to_binary([<<"{"/utf8>>,
															ClientProp,
														   <<"\"access_token\":\""/utf8>>, AccessToken, <<"\","/utf8>>,
														   <<"\"expires_in\":"/utf8>>, integer_to_binary(ExpireIn), <<","/utf8>>,
														   <<"\"resource_owner\":"/utf8>>, ResourceOwner, <<","/utf8>>,
														   <<"\"scope\":\""/utf8>>, Scope, <<"\","/utf8>>,
														   <<"\"refresh_token\":\""/utf8>>, case RefreshToken of
																									undefined -> <<>>;
																									_ -> RefreshToken
																							end, <<"\","/utf8>>, 
															<<"\"refresh_token_in\":"/utf8>>, case RefreshTokenExpireIn of 
																									undefined -> <<"0">>; 
																									_ -> integer_to_binary(RefreshTokenExpireIn) 
																							 end, <<","/utf8>>,
														   <<"\"token_type\":\""/utf8>>, TokenType, <<"\""/utf8>>,
													   <<"}"/utf8>>]),
					Request2 = Request#request{code = 200, 
											    reason = ok,
											    operation = oauth2_authenticate,
											    response_data = ResponseData2,
											    oauth2_grant_type = GrantType,
											    oauth2_access_token = AccessToken,
											    oauth2_refresh_token = RefreshToken,
											    client = Client,
											    user = User,
											    content_type_out = ?CONTENT_TYPE_JSON},
					ems_user:add_history(User2, Client2, Service, Request2),
					{ok, Request2};		
			{redirect, Client = #client{id = ClientId, redirect_uri = RedirectUri}} ->
					ClientIdBin = integer_to_binary(ClientId),
					ems_db:inc_counter(binary_to_atom(iolist_to_binary([<<"ems_oauth2_singlesignon_client_">>, ClientIdBin]), utf8)),
					LocationPath = iolist_to_binary([Protocol, <<"://"/utf8>>, Host, <<":"/utf8>>, integer_to_binary(Port), 
													 <<"/dados/login/index.html?response_type=code&client_id=">>, ClientIdBin, 
													 <<"&redirect_uri=">>, RedirectUri]),
					Request2 = Request#request{code = 302, 
												reason = ok,
											    operation = oauth2_redirect,
											    oauth2_grant_type = GrantType,
											    client = Client,
											    response_header = #{
																		<<"location">> => LocationPath
																	}
												},
					{ok, Request2};
			{error, Reason, ReasonDetail} ->
					% Para finalidades de debug, tenta buscar o user pelo login para armazenar no log
					case ems_util:get_user_request_by_login(Request) of
						{ok, UserFound} -> User = UserFound;
						_ -> User = undefined
					end,
					Request2 = Request#request{code = 401, 
											    reason = Reason,
											    reason_detail = ReasonDetail,
											    operation = oauth2_authenticate,
											    oauth2_grant_type = GrantType,
											    response_data = ?ACCESS_DENIED_JSON,
											    user = User},
					ems_user:add_history(case User of 
											undefined -> #user{};
											_ -> User
										 end,
										 #client{}, Service, Request2),
					{error, Request2}
		end
	catch
		_:_ ->
			Request3 = Request#request{code = 401, 
									   reason = access_denied,
									   reason_detail = eparse_oauth2_authorize_execute_exception,
									   operation = oauth2_authenticate,
									   response_data = ?ACCESS_DENIED_JSON},
			{error, Request3}
	end.

%% Requisita o código de autorização - seções 4.1.1 e 4.1.2 do RFC 6749.
%% URL de teste: GET http://127.0.0.1:2301/authorize?response_type=code2&client_id=s6BhdRkqt3&state=xyz%20&redirect_uri=http%3A%2F%2Flocalhost%3A2301%2Fportal%2Findex.html&username=johndoe&password=A3ddj3w
code_request(Request) ->
    try
		case ems_util:get_client_request_by_id(Request) of
			{ok, Client} ->
				case ems_util:get_user_request_by_login_and_password(Request) of
					{ok, User} ->
						RedirectUri = ems_util:to_lower_and_remove_backslash(ems_util:get_querystring(<<"redirect_uri">>, <<>>, Request)),
						Scope = ems_util:get_querystring(<<"scope">>, <<>>, Request),
						Authz = oauth2:authorize_code_request(User, Client, RedirectUri, Scope, []),
						case issue_code(Authz) of
							{ok, Response} ->
								Code = element(2, lists:nth(1, Response)),
								LocationPath = iolist_to_binary([RedirectUri, <<"?code=">>, Code]),
								Request2 = Request#request{code = 200, 
															reason = ok,
															operation = oauth2_authenticate,
															response_data = <<"{}">>,
															response_header = #{<<"location">> => LocationPath}},
								ems_user:add_history(User, Client, Request2#request.service, Request2),
								{ok, Request2};
							{error, Reason, ReasonDetail} ->
								Request2 = Request#request{code = 401, 
														reason = Reason,
														reason_detail = ReasonDetail,
														operation = oauth2_authenticate,
														response_data = ?ACCESS_DENIED_JSON},
								ems_user:add_history(User, Client, Request2#request.service, Request2),
								{error, Request2}
						end;
					{error, Reason, ReasonDetail} ->
						% Para finalidades de debug, tenta buscar o user pelo login para armazenar no log
						io:format("aqui1 ~p\n", [ems_util:get_user_request_by_login(Request)]),
						case ems_util:get_user_request_by_login(Request) of
							{ok, UserFound} -> io:format("aqui2\n"), User = UserFound;
							_ -> User = undefined
						end,
						Request2 = Request#request{code = 401, 
												   reason = Reason,
												   reason_detail = ReasonDetail,
												   operation = oauth2_authenticate,
												   response_data = ?ACCESS_DENIED_JSON},
						ems_user:add_history(case User of 
												undefined -> #user{};
												_ -> User
											 end,
											 #client{}, Request2#request.service, Request2),
						{error, Request2}
				end;
			{error, Reason, ReasonDetail} ->
				Request2 = Request#request{code = 401, 
											reason = Reason,
											reason_detail = ReasonDetail,
											operation = oauth2_authenticate,
											response_data = ?ACCESS_DENIED_JSON},
				{error, Request2}
		end
	catch
		_:_ ->
			Request3 = Request#request{code = 401, 
										reason = access_denied,
										reason_detail = eparse_code_request_exception,
										operation = oauth2_authenticate,
										response_data = ?ACCESS_DENIED_JSON},
			{error, Request3}
	end.

	
%%%===================================================================
%%% Funções internas
%%%===================================================================


%% Cliente Credencial Grant- seção 4.4.1 do RFC 6749. 
%% URL de teste: POST http://127.0.0.1:2301/authorize?grant_type=client_credentials&client_id=s6BhdRkqt3&secret=qwer
-spec client_credentials_grant(#request{}, #client{}) -> {ok, list(), #client{}} | {error, access_denied, atom()}.
client_credentials_grant(Request, Client) ->
	try
		Scope = ems_util:get_querystring(<<"scope">>, <<>>, Request),	
		Authz = oauth2:authorize_client_credentials(Client, Scope, []),
		issue_token(Authz, Client)
	catch
		_:_ -> {error, access_denied, eparse_client_credentials_grant_exception}
	end.


%% Resource Owner Password Credentials Grant - seção 4.3.1 do RFC 6749.
%% URL de teste: POST http://127.0.0.1:2301/authorize?grant_type=password&username=johndoe&password=A3ddj3w
-spec password_grant(#request{}, #client{}) -> {ok, list(), #client{}} | {error, access_denied, atom()}.
password_grant(Request, Client) -> 
	try
		case ems_util:get_user_request_by_login_and_password(Request) of
			{ok, User} ->
				Scope = ems_util:get_querystring(<<"scope">>, <<>>, Request),	
				case Client == undefined of
					true -> Authz = oauth2:authorize_password(User, Scope, []);
					false -> Authz = oauth2:authorize_password(User, Client, Scope, [])
				end,
				issue_token(Authz, Client);
			Error -> Error
		end
	catch
		_:_ -> {error, access_denied, eparse_password_grant_exception}
	end.

	
%% Verifica a URI do Cliente e redireciona para a página de autorização - Implicit Grant e Authorization Code Grant
%% URL de teste: GET http://127.0.0.1:2301/authorize?response_type=code&client_id=s6BhdRkqt3&state=xyz%20&redirect_uri=http%3A%2F%2Flocalhost%3A2301%2Fportal%2Findex.html
-spec authorization_request(#request{}, #client{}) -> {ok, list()} | {error, access_denied, atom()}.
authorization_request(Request, Client) ->
    try
		RedirectUri = ems_util:to_lower_and_remove_backslash(ems_util:get_querystring(<<"redirect_uri">>, <<>>, Request)),
		case ems_oauth2_backend:verify_redirection_uri(Client, RedirectUri, []) of
			{ok, _} -> {redirect, Client};
			_ -> {error, access_denied, einvalid_redirection_uri}
		end
	catch
		_:_ -> {error, access_denied, eparse_authorization_request_exception}
	end.


%% Requisita o código de autorização - seções 4.1.1 e 4.1.2 do RFC 6749.
%% URL de teste: GET http://127.0.0.1:2301/authorize?response_type=code2&client_id=s6BhdRkqt3&state=xyz%20&redirect_uri=http%3A%2F%2Flocalhost%3A2301%2Fportal%2Findex.html&username=johndoe&password=A3ddj3w
-spec refresh_token_request(#request{}, #client{}) -> {ok, list()} | {error, access_denied, atom()}.
refresh_token_request(Request, Client) ->
	try
		case ems_util:get_querystring(<<"refresh_token">>, <<>>, Request) of
			<<>> -> {error, access_denied, erefresh_token_empty};
			RefleshToken ->
				Scope = ems_util:get_querystring(<<"scope">>, <<>>, Request),
				Authz = ems_oauth2_backend:authorize_refresh_token(Client, RefleshToken, Scope),
				issue_token(Authz, Client)
		end
	catch
		_:_ -> {error, access_denied, eparse_refresh_token_request_exception}
	end.


%% Requisita o token de acesso com o código de autorização - seções  4.1.3. e  4.1.4 do RFC 6749.
%% URL de teste: POST http://127.0.0.1:2301/authorize?grant_type=authorization_code&client_id=s6BhdRkqt3&state=xyz%20&redirect_uri=http%3A%2F%2Flocalhost%3A2301%2Fportal%2Findex.html&username=johndoe&password=A3ddj3w&secret=qwer&code=dxUlCWj2JYxnGp59nthGfXFFtn3hJTqx
-spec access_token_request(#request{}, #client{}) -> {ok, list()} | {error, access_denied, atom()}.
access_token_request(Request, Client) ->
	try
		case ems_util:get_querystring(<<"code">>, <<>>, Request) of
			<<>> -> {error, access_denied, ecode_empty};
			Code -> 
				RedirectUri = ems_util:to_lower_and_remove_backslash(ems_util:get_querystring(<<"redirect_uri">>, <<>>, Request)),
				Authz = oauth2:authorize_code_grant(Client, Code, RedirectUri, []),
				issue_token_and_refresh(Authz, Client)
		end
	catch
		_:_ -> {error, access_denied, eparse_access_token_request}
	end.
	

issue_token({ok, {_, Auth}}, Client) ->
	case oauth2:issue_token(Auth, []) of
		{ok, {_, {response, AccessToken, 
							undefined,
							ExpiresIn,
							User,
							Scope, 
							RefreshToken, 
							RefreshTokenExpiresIn,
							TokenType
				 }
			}} ->
				{ok, [{<<"access_token">>, AccessToken},
						{<<"expires_in">>, ExpiresIn},
						{<<"resource_owner">>, User},
						{<<"scope">>, Scope},
						{<<"refresh_token">>, RefreshToken},
						{<<"refresh_token_expires_in">>, RefreshTokenExpiresIn},
						{<<"token_type">>, TokenType}], Client};
		_ -> {error, access_denied, einvalid_issue_token}
	end;
issue_token(_, _) -> {error, access_denied, eparse_issue_token_exception}.
    

issue_token_and_refresh({ok, {_, Auth}}, Client) ->
	case oauth2:issue_token_and_refresh(Auth, []) of
		{ok, {_, {response, AccessToken, 
							undefined,
							ExpiresIn,
							User,
							Scope, 
							RefreshToken, 
							RefreshTokenExpiresIn,
							TokenType
				 }
			}} ->
				{ok, [{<<"access_token">>, AccessToken},
						{<<"expires_in">>, ExpiresIn},
						{<<"resource_owner">>, User},
						{<<"scope">>, Scope},
						{<<"refresh_token">>, RefreshToken},
						{<<"refresh_token_expires_in">>, RefreshTokenExpiresIn},
						{<<"token_type">>, TokenType}], Client};
		_ -> {error, access_denied, einvalid_issue_token_and_refresh}
	end;
issue_token_and_refresh(_, _) -> 
	{error, access_denied, eparse_issue_token_and_refresh_exception}.


issue_code({ok, {_, Auth}}) ->
	case oauth2:issue_code(Auth, []) of
		{ok, {_, Response}} ->	{ok, oauth2_response:to_proplist(Response)};
		_ -> {error, access_denied, einvalid_issue_code}
	end;
issue_code(_) -> {error, access_denied, eparse_issue_code_exception}.

