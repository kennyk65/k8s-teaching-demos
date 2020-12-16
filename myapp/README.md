This is a sample nginx web application, suitable for running as a Docker application, and deploying to Kubernetes.

Build with "docker build -t myapp ."

Run with "docker run myapp:latest -p 8080:80"

Access via browser with "docker run  -p 8080:80 myapp:latest"