import { NgModule }      from '@angular/core';
import { Component } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { platformBrowserDynamic } from '@angular/platform-browser-dynamic';
import { HttpModule, JsonpModule } from '@angular/http';
import {FormsModule} from "@angular/forms";

import { NavigatorController } from './controller/navigator_controller'


@NgModule({
  imports: [
    BrowserModule,
    FormsModule, 
    HttpModule
  ],
  declarations: [  ],
  bootstrap: [  ]
})
export class DashboardModule { }



