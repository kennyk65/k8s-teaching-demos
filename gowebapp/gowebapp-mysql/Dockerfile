#TODO --- Define this image to inherit from the "mysql" version 5.6 base image
#https://hub.docker.com/_/mysql/
#https://docs.docker.com/engine/reference/builder/#from
FROM mysql:5.6

#TODO --- Investigate the "Initializing a Fresh Instance" instructions for the mysql 
#parent image, and copy the local gowebapp.sql file to the proper container directory 
#to be automatically executed when the container starts up 
#https://hub.docker.com/_/mysql/
#https://docs.docker.com/engine/reference/builder/#copy
COPY ./gowebapp.sql /docker-entrypoint-initdb.d

