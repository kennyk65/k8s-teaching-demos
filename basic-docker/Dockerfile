# Start with a base image from Dockerhub.  This contains nginx software:
FROM nginx

# Add our 3 web pages to the image
COPY *.html /usr/share/nginx/html/

# This container will expect traffic on port 80
EXPOSE 80

