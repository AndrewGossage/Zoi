# Zoi
Zoi is a server backend written in Zig that relies only on the standard library. Zoi is not a library but instead is essentially a template for you to use to create your own server in Zig. 


## What Does Zoi Do?
Zoi is a backend that is coded in Zig and configured in json (previously in toml). It features a custom callback based router with support for parameters and limited support for wildcards.
It contains functionality for serving static files and a very rudimental templating system. 

## How to use Zoi
You should make changes to src/main.zig and src/routes.zig to set up your routes and logic; then run `zig build run`. Zoi is built for Zig 0.15. 

## [Thanatos](https://github.com/AndrewGossage/Thanatos)
Thanatos is an example of using Zoi as an alternative to something like Tauri or Electron.
