# Zoi
Ultra simple zig server for http 1.1 over tcp.
Zoi delivers static pages over http 1.1 without relying on any external dependencies. All you need is the Zoi source code and Zig. Zoi is released under the MIT license. If you are wanting to deliver static web pages just put some html/css/js files in the directory where you run Zoi and it will automatically serve any files it finds. I make no guarantees that it is stable but I am constantly working to make improvements both to stability and usability. You can feel free to make suggestions on ways it could be improved or even contribute improvements yourself if that is something that would interest you. Zoi runs on 0.11 dev.


### Why Use Zoi?
That's a good question and Zoi might not be the right choice for you. I built it and continue to build it mostly as a practice exercise for using Zig. That being said, a great benefit of Zoi is that it is incredibly simple. Anyone can learn all its inner workings fairly easily. It would work as a great foundation to hack on and add any features you would like it to have. As a side note although speed is not necessarily a main goal of Zoi it does run lean and tends to have reasonably good response times. 

### Instructions
#### Static Content
Just put the files you want to be able to deliver as static web pages in the same directory where you run the command to start the server. This can be done by running "zig build run" in the top level directory of the project. Zoi expects an index.html file and a 404.html file to be present at minimum. On the official site I have noticed that it can hang up when not periodically restarted. I am currently using automation for that to hopefully keep it running smoothly. 

#### Dynamic Content
Zoi can handle dynamic content by replacing 'server.accept' with 'server.acceptAdv' in the server loop function in main.zig. You then pass in a struct that has an 'accept' function. This function needs to take in a struct as its only argument. There is a simple example of how to do this in main.zig. 

#### Running Zoi
The port and host are chosen based on zoi.toml. Currently this is all the zoi.toml file does and toml parsing is not complete. However, as new features are added I will improve toml reading. In its default configuration Zoi runs on localhost:8080. If you want to run this in production change the host to {0,0,0,0} and port to 80 in zoi.toml. You will need to allow access to port 80 through your firewall.  If you want added security or load balancing you could instead run another server between Zoi and the outside internet by using port forwarding. 

### Latest Updates
#### Nov 13 2023
Partially fixed an issue with toml reading where toml would only parse if only one section was present. Currently the \[server\] section still needs to be listed first but that will be fixed soon.

#### Oct 3 2023
The general purpose allocator used for server.accept is now shared across calls. Potential leaks for append calls to arrayLists in multiple functions have been fixed.

#### Sep 6 2023
In the zoi.toml you now specify which filetypes you will allow to go out, this is for security. Hidden files and folders are excluded from going out altogether for security purpose20s.




### Needed Work
1. Supplemental accept functions need to be updated and code needs to be cleaned up. Files with no extension should pull a '.html' file.
2. Currently Zoi reads naively assuming that 1 read will pull 1 request. This is unlikely to cause major issues but should be updated.
