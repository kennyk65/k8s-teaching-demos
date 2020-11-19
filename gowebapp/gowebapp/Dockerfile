#TODO --- Define this image to inherit from the "ubuntu" base image
#https://hub.docker.com/_/ubuntu
#https://docs.docker.com/engine/reference/builder/#from
FROM ubuntu

EXPOSE 80

#TODO --- Copy source code in the ./code directory into /opt/gowebapp
#https://docs.docker.com/engine/reference/builder/#copy
COPY ./code /opt/gowebapp

#TODO --- Copy the application config in the ./config directory into 
#/opt/gowebapp/config
COPY ./config /opt/gowebapp/config

WORKDIR /opt/gowebapp/

#TODO --- Define an entrypoint for this image which executes the gowebapp 
#application (/opt/gowebapp/gowebapp) when the container starts
#https://docs.docker.com/engine/reference/builder/#entrypoint
ENTRYPOINT [ "/opt/gowebapp/gowebapp" ]