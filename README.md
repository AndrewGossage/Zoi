# Zoi
Ultra simple zig server for http 1.1 over tcp.
Zoi delivers static pages over http 1.1 without relying on any external dependencies. All you need is the Zoi source code and Zig. Zoi is released under the MIT license. If you are wanting to deliver static web pages just put some html/css/js files in the directory where you run Zoi and it will automatically serve any files it finds. I make no guarantees that it is stable but I am constantly working to make improvements both to stability and usability. You can feel free to make suggestions on ways it could be improved or even contribute improvements yourself if that is something that would interest you. Zoi runs on 0.11 dev.


### Why Use Zoi?
That's a good question and Zoi might not be the right choice for you. I built it and continue to build it mostly as a practice exercise for using Zig. That being said, a great benefit of Zoi is that it is incredibly simple. Anyone can learn all its inner workings fairly easily. It would work as a great foundation to hack on and add any features you would like it to have. As a side note although speed is not necessarily a main goal of Zoi it does run lean and tends to have reasonably good response times. 

### Instructions
#### Static Content
Just put the files you want to be able to deliver as static web pages in the same directory where you run the command to start the server. This can be done by running "zig build run" in the top level directory of the project. Zoi expects an index.html file and a 404.html file to be present at minimum. On the official site I have noticed that it can hang up when not periodically restarted. I am currently using automation for that to hopefully keep it running smoothly. 

#### Dynamic Content
Zoi can handle dynamic content, there is an example struct in main.zig that can be used or replaced. By defail this struct will handle requests to "/echo" and "/testing.html" anything else will be handled as a request for static content. Also, because of how easy it is to hack on top of Zoi you can  fairly easily embed a scripting language if that is your cup of tea. 

#### Running Zoi
The port and host are chosen based on zoi.toml. Currently this is all the zoi.toml file does and toml parsing is not complete. However, as new features are added I will improve toml reading. In its default configuration Zoi runs on localhost:8080. If you want to run this in production change the host to {0,0,0,0} and port to 80 in zoi.toml. You will need to allow access to port 80 through your firewall.  If you want added security or load balancing you could instead run another server between Zoi and the outside internet by using port forwarding. 

### Latest Updates

#### Jan 1 2023
Server no longer assumes a single read will fetch the entirety of the request header (server will refuse to process request over 3 kb). server.acceptAdv has replaced server.accept entirely and has been renamed for the purpose. 

#### Dec 30 2023
Added ability to add headers to response 

#### Dec 28 2023
Now sends body of post request to router, no longer sends raw buffer, get request url params no longer cause error, however, they are currently just ignored. Will pull entire content body of post request up to 1 megabyte.
Significatly improved parsing of zoi.toml server section no longer has to be first section in document. I now use standard substring finding functions instead of manually checking for each substring. Added support for urls with no file extension.

#### Dec 27 2023
Added header parsing and support for dynamic content, Manual router in main.zig is now active by default but is only coded to handle requests to "/test.html" and "/echo", anything else will go to a new fallback method that will handle any un processed request as a request for a static page. 

#### Nov 19 2023
Accept adv has been updated with improvements to regular accept function.

#### Nov 13 2023
Partially fixed an issue with toml reading where toml would only parse if only one section was present. Currently the \[server\] section still needs to be listed first but that will be fixed soon.

#### Oct 3 2023
The general purpose allocator used for server.accept is now shared across calls. Potential leaks for append calls to arrayLists in multiple functions have been fixed.

#### Sep 6 2023
In the zoi.toml you now specify which filetypes you will allow to go out, this is for security. Hidden files and folders are excluded from going out altogether for security purpose20s.


### Needed Work
1. Roadmap for future development
2. URL query string parsing
