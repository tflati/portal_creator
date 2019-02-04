#!/bin/bash

DJANGO_PORT="7565"
NEO4J_DATA_PORT=""
NEO4J_BROWSER_PORT=""
DJANGO_PROJECT_NAME="radiation"
APACHE_PROJECT_NAME="radiation"
BASEDIR="$HOME/radiation_project"
VERSION="3.4.0"
GIT_URL="https://github.com/tflati/radiation.git"

SCRIPT_DIR=$(pwd)

if [ ! -d $BASEDIR ]
then
	mkdir $BASEDIR
fi

cd $BASEDIR

function userOK {
	read -p "Press enter to continue"
}

echo "Creating start and stop scripts..."
userOK
truncate -s 0 start.sh
if [ ! -z $NEO4J_DATA_PORT ]
then
	echo "sudo neo4j-community-$VERSION/bin/neo4j start " >> start.sh
fi

echo "PORT=$DJANGO_PORT" >> start.sh
echo "python3.5 project/django_server/manage.py runserver \$PORT" >> start.sh
chmod +x start.sh

truncate -s 0 stop.sh
if [ ! -z $NEO4J_DATA_PORT ]
then
	echo "sudo neo4j-community-$VERSION/bin/neo4j stop " >> stop.sh
fi
echo "PORT=$DJANGO_PORT" >> stop.sh
echo "ps x | grep \"runserver\" | grep \$PORT | sed 's/^ //g' | cut -d' ' -f 1 | xargs kill" >> stop.sh
chmod +x stop.sh

if [ ! -z "$GIT_URL" ]
then
	echo "Init git project"
	userOK
	echo "# $DJANGO_PROJECT_NAME" >> README.md
	git init
	git add README.md
	git commit -m "first commit"
	git remote add origin $GIT_URL
	git push -u origin master
fi

if [ ! -z $NEO4J_DATA_PORT ]
then
	######################################
	############ NEO4J ##################
	######################################

	# Download Neo4j
	echo "Downloading neo4j"
	userOK
	wget https://neo4j.com/artifact.php?name=neo4j-community-$VERSION-unix.tar.gz
	
	echo "Unpacking neo4j"
	userOK
	tar xzvf artifact.php\?name\=neo4j-community-$VERSION-unix.tar.gz
	echo "Removing neo4j temporary arhive file"
	userOK
	rm artifact.php\?name\=neo4j-community-$VERSION-unix.tar.gz

	# Disabling authentication:
	echo "Disabling authentication"
	userOK
	sed -i 's/#dbms.security.auth_enabled=false/dbms.security.auth_enabled=false/g' neo4j-community-$VERSION/conf/neo4j.conf

	# Change the default BOLT listen port (7687) to your favourite port:
	echo "Changing default BOLT listen port (7687) to project's specific port ($NEO4J_DATA_PORT)"
	userOK
	sed -i "s/#dbms.connector.bolt.listen_address=:7687/dbms.connector.bolt.listen_address=:$NEO4J_DATA_PORT/g" neo4j-community-$VERSION/conf/neo4j.conf

	# Change the default HTTP port (7474) for browsing data:
	echo "Changing default HTTP port (7474) for browsing data ($NEO4J_BROWSER_PORT)"
	userOK
	sed -i "s/#dbms.connector.http.listen_address=:7474/dbms.connector.http.listen_address=:$NEO4J_BROWSER_PORT/g" neo4j-community-$VERSION/conf/neo4j.conf

	# Disabling HTTPS access
	echo "Disabling HTTPS access"
	userOK
	sed -i "s/dbms.connector.https.enabled=true/dbms.connector.https.enabled=false/g" neo4j-community-$VERSION/conf/neo4j.conf
fi

######################################
############ DJANGO ##################
######################################
echo "Creating project directory"
userOK
mkdir project
cd project

echo "Creating a new Django project"
userOK
django-admin startproject django_server
cd django_server

echo "Creating new app called $DJANGO_PROJECT_NAME"
userOK
python3 manage.py startapp $DJANGO_PROJECT_NAME

if [ ! -z $NEO4J_DATA_PORT ]
then
	echo "Setting database port in django app ($NEO4J_DATA_PORT)"
	userOK
	echo -e "\n\nfrom neomodel import config\nconfig.DATABASE_URL = 'bolt://neo4j:password@localhost:$NEO4J_DATA_PORT'" >> django_server/settings.py
fi

# Disabling Django's CSRF view
echo "Disabling Django's CSRF view"
userOK
sed -i "s/'django.middleware.csrf.CsrfViewMiddleware'/#'django.middleware.csrf.CsrfViewMiddleware'/g" django_server/settings.py

#Setup the port for the API
grep ${DJANGO_PROJECT_NAME} /etc/apache2/sites-available/000-default.conf > /dev/null
if [ $? -eq 1 ]
then
	echo "Setting ProxyPass/ProxyPassReverse into Apache configuration file (port $DJANGO_PORT)"
	userOK
	sudo sed -i "s#</VirtualHost>#\n\tProxyPass /${DJANGO_PROJECT_NAME}_api/ http://localhost:$DJANGO_PORT/\n\tProxyPassReverse /${DJANGO_PROJECT_NAME}_api/ http://localhost:$DJANGO_PORT/\n\n</VirtualHost>#g" /etc/apache2/sites-available/000-default.conf
	
	echo "Restarting apache2"
	userOK
	sudo service apache2 restart
fi

cp django_server/urls.py $DJANGO_PROJECT_NAME/

echo "Enabling urls specific to the new Django app"
userOK
sed -i "s#urlpatterns = \[#from django.conf.urls import url\nfrom django.conf.urls import include\n\nurlpatterns = \[\n    url(r'^$DJANGO_PROJECT_NAME/', include('$DJANGO_PROJECT_NAME.urls')),#g" django_server/urls.py
sed -i "s#path('admin/', admin.site.urls),##g" $DJANGO_PROJECT_NAME/urls.py

echo "Activating Django project (migration)"
userOK
python3 manage.py migrate

cd ..

######################################
######### HTML ENGINE ################
######################################

if [ ! -z "$GIT_URL" ]
then
	echo "Cloning Interface-Engine project (as submodule)..."
	userOK
	git submodule add https://github.com/tflati/interface-engine.git engine
else
	echo "Cloning Interface-Engine project (as zip package)..."
	wget https://github.com/tflati/interface-engine/zipball/master/ -O engine.zip
	unzip engine.zip
	mv tflati-interface-engine* engine
	rm engine.zip
fi

cd engine
echo "Installing bower components..."
userOK
bower install
cd ..

# Creare un link simbolico dentro la cartella /var/www/html
echo "Creating symbolic link in Apache web directory"
userOK
sudo ln -s `readlink -f engine/` /var/www/html/$APACHE_PROJECT_NAME

sed -i 's/interface-engine/'$APACHE_PROJECT_NAME'/g' engine/index.html
sed -i 's#<base href="/.*/">#<base href="/'$APACHE_PROJECT_NAME'/">#g' engine/index.html
sed -i 's/interface-engine/'$APACHE_PROJECT_NAME'/g' engine/components/element/elementController.js
sed -i 's/interface-engine/'$APACHE_PROJECT_NAME'/g' engine/components/table/my_custom_element/myCustomElement.js

echo "Creating symbolic link from engine directory to material directory."
userOK
mkdir material
mkdir material/imgs/
mkdir material/downloads/
cp $SCRIPT_DIR/config.json material
for file in $(ls material/)
do
	echo "Creating symlink from engine/$file to material/$file"
	ln -s ../material/$file engine/$file
done

cd ..

######################################
######### RUN SERVERS ################
######################################

echo "Current directory:"
pwd

if [ ! -z $NEO4J_DATA_PORT ]
then
	echo "Launching Neo4j server on port $NEO4J_DATA_PORT"
	userOK
	sudo neo4j-community-$VERSION/bin/neo4j start

	# Wait for the service to come up before testing
	sleep 5
	echo "Checking Neo4j server is OK"
	sudo neo4j-community-$VERSION/bin/neo4j status
	
	# Open Neo4j in browser
	echo "Opening Neo4j browser at port $NEO4J_BROWSER_PORT"
	userOK
	firefox localhost:$NEO4J_BROWSER_PORT
fi

echo "Launching Django server on port $DJANGO_PORT"
userOK
./start.sh

# Open project in browser
echo "Opening project in browser"
userOK
firefox localhost/$APACHE_PROJECT_NAME

