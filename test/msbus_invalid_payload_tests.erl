-module(msbus_invalid_payload_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("stdlib/include/qlc.hrl").
-include("../include/msbus_schema.hrl").

	
start_server_test() ->
	msbus_logger:info("========= Testes invalid payload ==========="),
	file:set_cwd("/home/agilar/Dropbox/workspace/erlang/erlangMS/msbus"),
	code:add_path("/home/agilar/Dropbox/workspace/erlang/erlangMS/msbus/deps/jsx/ebin"),
	application:start(msbus),
	application:start(inets),
	ok.

dominio() -> "http://localhost:2301".

invalid_payload_test() ->
	msbus_logger:info("\n\nTEST: Envia um payload invalido e retorna invalid_payload"),
	Payload = <<")(*(&*($#%#@$@$#$%*&)()(&*&#$@#@!#@%$#%$#%$#%$#$#@$#@!#@ajpoiuroqwunroiqpweiuroqyi7YRe">>,
	HTTPHeader = [],
	Url = dominio() ++ "/user",
	Request = {Url, HTTPHeader, "application/json", Payload},
	{ok, {{_Version, 415, _ReasonPhrase}, _Headers, _Body}} = httpc:request(post, Request, [], []).


payload_em_branco_test() ->
	msbus_logger:info("\n\nTEST: Envia um payload em branco para falhar o servico e retornar servico_falhou."),
	Payload = "",
	HTTPHeader = [],
	Url = dominio() ++ "/user",
	Request = {Url, HTTPHeader, "application/json", Payload},
	{ok, {{_Version, 502, _ReasonPhrase}, _Headers, _Body}} = httpc:request(post, Request, [], []).


	
stop_server_test() ->
	msbus_logger:info("Finalizando os testes..."),
	msbus_util:sleep(1000),
	application:stop(inets),
	application:stop(msbus),
	ok.
	



