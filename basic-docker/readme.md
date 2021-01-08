
Demo will only run in a linux environment
Be sure Docker is running
Show index files
Show Dockerfile
Run:  docker build -t simple .
Run:  docker images
Open 2 other terminal shell
In one run:  watch "docker ps -a"
In one run:  netstat -an | grep 8080
Run:  docker run --name demo -dp 8080:80 -t simple
Run:  docker ps -a
  - This shows the container process running.
Run:  docker stop demo
  - This stops the running process
Run:  docker ps -a
  - This shows the container is still present, just not running.  The files and thin read/write layer are there
Run:  docker start demo
  - This restarts
Run:  docker stop demo
Run:  docker rm demo