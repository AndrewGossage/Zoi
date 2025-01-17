# Zoi
This branch is for version 2. Version 2 is a WIP and is incompatible with the old version.
Zoi is a backend written in Zig and relies only on the standard library. Zoi is not a library but instead is  essentially a template for you to use to create your own backends in Zig. 

## Version 2
Version 2 was build almost entirely from the ground up and uses the standard library's http server instead of a homespun one. It is very much a work in progress so you should expect breaking changes frequently.
Zoi is not production ready without making your own changes. Version 2 is build to be much more flexible and usable than the previous version. 

## What Does Zoi Do?
Zoi is a backend that is coded in Zig and configured in json (previously in toml). It features a custom callback based router with support for parameters and limited support for wildcards.
It contains functionality for serving static files and a very rudimental templating system. 

## How to use Zig
You should make changes to src/main.zig to set up your routes and logic; then run `zig build run`. Zoi is build for Zig 0.14. Using Zoi will require some trial and error since I have not written any 
documentation for the new version yet.
