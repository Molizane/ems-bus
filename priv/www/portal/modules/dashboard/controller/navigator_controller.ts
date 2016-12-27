import { Component, NgZone } from '@angular/core';
import { SitemapService } from '../service/sitemap_service';


interface fpc {
    configFields: Function;
}

declare var fpc: fpc;

@Component({
	selector: 'navigator',
	providers: [SitemapService],
	templateUrl: 'modules/dashboard/web/navigator.html'
})
export class NavigatorController { 
	public sitemap : any = { "name": "dashboard",
						     "title": "Dashboard",
							 "url": "/portal/dashboard",
							 "image_url": "modules/dashboard/img/pedidos.png",
							 "items": []};
	public current : any = [];
	public current_page : number = 1;
	public current_url : string = undefined;
	public breadcrumb : any = null;
	
	constructor(private sitemapService: SitemapService, private _ngZone: NgZone) {
		
	}

	ngOnInit() {
		this.sitemapService.getSitemap().subscribe(res => {
				this.sitemap = res;
				this.current = this.sitemap;
				this.breadcrumb = this.get_breadcrumb(this.current);
		});
    }
  	
  	ngAfterViewInit() {
		console.log("passou aqui");
  	}
  	
  	
	go(item : any){
		if (item.items == undefined){
			if (item.component == undefined || item.component == ""){
				this.current = this.sitemap;
			}else{
				this.current = item;
			}
		}else{
			this.current = item;
		}
	
		this.breadcrumb = this.make_breadcrumb(this.current, []);
			
		// Executado após renderizar a tela para configurar os inputs com a biblioteca fpc
		this._ngZone.onMicrotaskEmpty
		  .subscribe(() => {
				this._ngZone.run(() => {
					this._ngZone.run(() => { 		
						fpc.configFields(); 
					});
				});
		  });
		
	}
	
	private get_breadcrumb(item : any){
		return this.make_breadcrumb(item, []);
	}
	
	private make_breadcrumb(item : any, result : any){
		if (item.owner != null){
			this.make_breadcrumb(item.owner, result);
		}		
		if (item.name != "dashboard"){
			result.push(item);
		}
		return result;
	}
	
	setCurrentPage(page : any){
		this.current_page = parseInt(page);
	}

}


