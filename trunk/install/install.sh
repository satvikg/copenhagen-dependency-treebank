#!/bin/bash

# Settings
user=cdt
home=/home/$user
svnpasswd=$home/.svnpasswd
svnuser=$home/.svnuser
cdtdir=$home/cdt
installdir=$cdtdir/install

# Prompt for Google user name and password
if [ ! -f $svnuser ] ; then
	echo "Enter your user name and password. Please be very careful when typing!"
	echo -n "Google code username (email): "
	read user
	echo $user > $svnuser
	echo -n "Google code password: "
	read passwd
	echo $passwd > $svnuser
	chown $user $svnuser $svnpasswd
fi

# Get user and password
cd $home
username=`cat $svnuser`
password=`cat $svnpasswd`

# Checkout CDT repositorym -r $home/cdt
if [ ! -d cdt ] ; then
	svn checkout https://copenhagen-dependency-treebank.googlecode.com/svn/trunk/ cdt --username $username --password $password
else
	echo "ERROR: Directory $home/cdt already exists!"
fi

# Copy DTAG icon to desktop
cp $installdir/DTAG.desktop $home/Desktop

# Extract dtag archive
echo
echo "Please log in as root and execute the following command:"
echo "    sh $installdir/install-root.sh"


