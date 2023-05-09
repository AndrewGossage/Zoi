# Zoi
Ultra simple zig server for http 1.1 over tcp.
Zoi delivers static pages over http 1.1 without relying on any external dependencies. All you need is the Zoi source code, and Zig. Zoi is released under the MIT license. If you are wanting to deliver static web pages just put some html/css/js files in the directory where you run Zoi and it will automatically serve any files it finds. I make no guarantees that it is stable but I am constantly working to make improvements both to stability and usability. You can feel free to make suggestions on ways it could be improved or even contribute improvements yourself if that is something that would interest you. Zoi runs on 0.11 dev.

### Updates
Zoi now runs multithreaded! Specify the number of threads in zoi.toml in the server section with the key of "workers".

### Why Use Zoi?
That's a good question and Zoi might not be the right choice for you. I built it and continue to build it mostly as a practice exercise for using Zig. That being said, a great benefit of Zoi is that it is incredibly simple. Anyone can learn all its inner workings fairly easily. It would work as a great foundation to hack on and add any features you would like it to have. As a side note although speed is not necessarily a main goal of Zoi it does run lean and tends to have reasonably good response times. 

### Instructions
#### Static Content
Just put the files you want to be able to deliver as static web pages in the same directory where you run the command to start the server. This can be done by running "zig build run" in the top level directory of the project. Zoi expects an index.html file and a 404.html file to be present at minimum.

#### Dynamic Content
Zoi can handle dynamic content by replacing 'server.accept' with 'server.acceptAdv' in the server loop function in main.zig. You then pass in a struct that has an 'accept' function. This function needs to take in a struct as its only argument. There is a simple example of how to do this in main.zig. 

#### Running Zoi
The port and host are chosen based on zoi.toml. Currently this is all the zoi.toml file does and toml parsing is not complete. However, as new features are added I will improve toml reading. In its default configuration Zoi runs on localhost:8080. If you want to run this in production change the host to {0,0,0,0} and port to 80 in zoi.toml. You will need to allow access to port 80 through your firewall.  If you want added security or load balancing you could instead run another server between Zoi and the outside internet by using port forwarding. 
