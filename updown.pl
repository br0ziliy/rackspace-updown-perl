#!/usr/bin/perl

# Rackspace MyCloud server management script
# Vasyl Kaigorodov <vkaygorodov@gmail.com>
# (cc) 2012

use strict;
use warnings;
use LWP;
use JSON;
use Data::Dumper;
use Getopt::Long;
use Net::SMTP::SSL;

$| = 1; # disable output buffering so we get the progress disaplyed correctly

# Initialize Rackspace API authentication endpoints for both US and UK locations
my %locations = (
	"US" => #
	"UK" => #

);

# Rackspace authentication hash via username + API key
my $rs_auth = { auth => { 
		'RAX-KSKEY:apiKeyCredentials' => { 
			username => 'user', 
			apiKey => 'key'
		} 
	   }
};
my $json_opts = { utf8 => 1, pretty => 0 }; # Enable UTF-8 support for JSON, disable pretty formatting
my $ua = LWP::UserAgent->new(); # Create a new "browser" object to communicate to Rackspace
$ua->cookie_jar({}); # Add cookies support for "browser"

my $server_id = undef;		#
my $server_name = undef;	#
my $flavor_id = undef;		# Initialization of configuration variables with undefined value
my $image_id = undef;		# These will be defined later
my $image_name = undef;		#

my %conf = get_config(); # Initialize "browser" configuration - authenticate to Rackspace API and get the management endpoints URLs

my $ep = $conf{endpoint}{dfw}; # $ep holds management endpoint URL

# Command-line options processing
GetOptions(
	'server-id=s' => \$server_id,
	'flavor-id=s' => \$flavor_id,
	'server-name=s' => \$server_name,
	'image-id=s'  => \$image_id,
	'image-name=s' => \$image_name,
	'list-images' => sub { get_images(); exit; },
	'list-servers' => sub { get_servers(); exit; },
	'list-flavors' => sub { get_flavors(); exit; },
	'start-server' => sub { start_server(); exit;},
	'stop-server' => sub { stop_server(); exit;},
);

# We should not get here if script completed succesfully
print "END\n";exit;

sub get_config {
	# Initialize empty hash which will hold authentication token and 
	# Management endpoints URLs for US and UK
	my %access_hash = (
		token => '',
		expires => '',
		endpoint => {
			dfw => '',
			ord => '',
		},
	);

	# Create JSONified authentication string to pass to the authentication endpoint
	my $rs_auth_json = to_json($rs_auth,$json_opts);

	# Make the POST request to the authentication endpoint to get the authentication token and
	# management endpoint URLs
	my $res = $ua->post( $locations{"US"}, 
				'Content-Type' => 'application/json; charset=utf-8',
				'Content' => $rs_auth_json,
				);
	# $res->content holds JSON responce from 
	# Rackspace API authentication server -
	# decode that for later processing
	my $access = from_json($res->content);

	# Save the authentication token in the local hash
	$access_hash{expires} = $access->{'access'}{'token'}{'expires'};
	$access_hash{token} = $access->{'access'}{'token'}{'id'};

	# Iterate through the Rackspace response and find the management API endpoint URLs
	for (my $i=0;$i<=7;$i++){
		if( $access->{'access'}{'serviceCatalog'}[$i]{'name'} eq "cloudServersOpenStack" ) { 
			$access_hash{endpoint}{dfw} = $access->{'access'}{'serviceCatalog'}[$i]{'endpoints'}[0]{'publicURL'};
			$access_hash{endpoint}{ord} = $access->{'access'}{'serviceCatalog'}[$i]{'endpoints'}[1]{'publicURL'};
		};
	}

	# return the filled hash to initialize global hash %conf
	return %access_hash;
}

sub get_images {

	# Get images names and IDs and print these out OR return the image data
	# $id is optional parameter (function will return a hash which hold the image details)
	# $filter is optional parameter to filter the output
	my $filter = shift;
	my $id = shift;

	# API request to list all images
	my $res = $ua->get($ep."/images/detail?".($filter?$filter:""), "X-Auth-Token" => $conf{token} );
	my $images = from_json($res->content);

	# $images now contain a hash reference to an array which holds all images details
	my $sz = scalar(@{ $images->{images} }); # get the images array size

	# Iterate through an images array and eiither
	# print the images list or return the needed image details for later processing	
	for (my $i=0;$i < $sz;$i++) {
		if ((defined($id)) and ($images->{images}[$i]{id} eq $id)) { return $images->{images}[$i]; }
		else { print "[".$images->{images}[$i]{id}."]: ".$images->{images}[$i]{name}."\n"; }
	}
}

sub get_servers {
	# Works exactly like get_images, but prints out or returns details for a server
	my $filter = shift;
	my $id = shift;
	my $res = $ua->get($ep."/servers/detail?".($filter?$filter:""), "X-Auth-Token" => $conf{token} );
	my $servers = from_json($res->content);
	my $sz = scalar(@{$servers->{servers}});
	for (my $i=0;$i < $sz;$i++) {
		if ((defined($id)) and ($servers->{servers}[$i]{id} eq $id)) {
			return $servers->{servers}[$i];
		}
		else { print "[".$servers->{servers}[$i]{id}."]: ".$servers->{servers}[$i]{name}."\n"; }
	}
}

sub get_flavors {
	# Works exactly like get_images and get_servers, but prints out or returns details for a server flavour
	my $filter = shift;
	my $id = shift;
	my %flavor_hash = (
	id => '',
	name => '',
	);
	my $res = $ua->get($ep."/flavors?".($filter?$filter:""), "X-Auth-Token" => $conf{token} );
	my $flavors = from_json($res->content);
	my $sz = scalar(@{$flavors->{flavors}});
		for (my $i=0;$i < $sz;$i++) {
			if ((defined($id)) and ($flavors->{flavors}[$i]{id} eq $id)) { return $flavors->{flavors}[$i]; }
			else { print "[".$flavors->{flavors}[$i]{id}."]: ".$flavors->{flavors}[$i]{name}."\n"; }
		}
}
sub start_server {
	# Function to create a server from an image
	# image-id and flavor-id should be set in the configuration file already
	# server-name is optional (script will use "apitest" as default server name)

	$flavor_id = getconfig("flavor-id");
	$image_id = getconfig("image-id");
	$server_name = getconfig("server-name");

	# Check if needed parameters set and exit if not, or print the parameters and continue
	if ((not defined($flavor_id)) or (not defined($image_id))) {
		print "Flavor ID or Image ID not found in the configuration file. Exiting.\n";
		exit 2;
	} else {
		print "start_server: $flavor_id $image_id\n";
	}

	my $flavor = get_flavors("", $flavor_id); # get flavor details
	my $image = get_images("", $image_id);    # get image details

	# Initialize the request to create the server
	my $request = { server =>  {
				name => "AUTO_".$server_name,
				imageRef => $image->{id},
				flavorRef => $flavor->{id},
				'OS-DCF:diskConfig' => 'AUTO',

	}};

	# encode the request to JSON
	my $req_content = to_json($request,$json_opts);

	# Make a request to Rackspace API which actually starts the server creation
	my $res = $ua->post($ep."/servers",
				'Content-Type' => 'application/json; charset=utf-8',
				'Content' => $req_content,
				"X-Auth-Token" => $conf{token}, );
	my $server = from_json($res->content);

	# $server now holds a hash reference with the progress of
	# server creation, root password and server ID
	print "Build in progress\n";
	my $s; # temporary variable to hold the server details
	print "Progress:";

	# Get server details each 20 seconds and print the progress output
	# until the progress is 100%
	do {
		print " ";
		sleep(20);
		$s = get_servers("",$server->{server}{id});
		print $s->{progress}."%";

	} while ( $s->{progress} < 100 );

	# Delete the old image we just used to create a new server - it's not needed anymore
	delete_image($s->{image}{id});
	# Record created server ID to file
	putconfig("server-id",$s->{id});

	# Format an e-mail message with the server access details and send the e-mail
	my $str = "\nServer built.\n";
	$str .= "IPv".$s->{addresses}{public}[0]{version}.": ".$s->{addresses}{public}[0]{addr}."\n";
	$str .= "IPv".$s->{addresses}{public}[1]{version}.": ".$s->{addresses}{public}[1]{addr}."\n";
	$str .= "Password: ".$server->{server}{adminPass}."\n";
	sendmail("Server started",$str);
}
sub delete_image {
	# Just delete an image
	my $id = shift;
	my $res = $ua->delete($ep."/images/".$id, "X-Auth-Token" => $conf{token});
}

sub stop_server {
	# Create an image from the running server and then stop it.
	# server-id should be set in the configuration file
	$server_id = getconfig("server-id");

	# Check if server-id was found, and exit if it's not
	if (not defined($server_id)) {
		print "Server ID not found in the configuration file. Exiting.\n";
		exit 2;
	} else {
		print "stop_server: $server_id\n";
	}

	# Get the running server details
	my $server = get_servers("",$server_id);

	# Create an image from the running server.
	# Image name will be always "apiimage"
	create_image("apiimage",$server->{id});

	# Delete the server and send an e--mail about it
	my $res = $ua->delete($ep."/servers/".$server->{id}, "X-Auth-Token" => $conf{token});
	print "\nServer deleted.\n";
	sendmail("Server deleted","Server ".$server->{id}." has been deleted");
}

sub create_image {

	# Create an image from running server.
	my $name = shift; # Image name
	my $sid = shift;  # Running server ID
	print "create_image: $name $sid\n";

	# Initialize request, encode it to JSON and send the request
	my $request = { createImage =>  {
				name => "AUTO_".$name,
	}};
	my $req_content = to_json($request,$json_opts);
	my $res = $ua->post($ep."/servers/".$sid."/action",
				'Content-Type' => 'application/json; charset=utf-8',
				'Content' => $req_content,
				"X-Auth-Token" => $conf{token}, );
	# ID of the image to be created is 
	# returned in the Location HTTP header - got and get it!
	my $i_url = $res->header('Location');

	# Actually get the image ID
	my $iid = (split("/",$i_url))[-1];
	my $i; # temporary variable to hold created image details
	print "Progress:";

	# Get the created image details each 20 seconds
	# and print the progress until progress reaches 100%
	do {
		print " ";
		sleep(20);
		my $result = $ua->get($ep."/images/".$iid, "X-Auth-Token" => $conf{token},);
		$i = from_json($result->content);
		print $i->{image}{progress}."%";

	} while ( $i->{image}{progress} < 100 );

	# Record the image ID to the configuration file
	putconfig("image-id",$i->{image}{id})
}

sub putconfig {

	# Records values to the configuration file
        my $key = shift; # variable name
        my $value = shift; # variable value

	# Open configfile and temporary file
        open(CF,"<","./updown.cfg");
        open(TMP,">","./updown.cfg.tmp");

	# iterate through the file, find the variable to operate on and replace that with the new value
        while(<CF>) {
                if ( $_ =~ /^$key=.*/ ){
                        $_ =~ s/^$key=.*/$key=$value/;
                }
                print TMP $_;
        }
        close CF;  # close files - we dont need that anymore
	close TMP; #

	# delete original file
	unlink("./updown.cfg");

	# Windows compatibility - use Perl native function if running under Linux,
	# or rename with the OS buil-in instead
	if ( $^O eq "linux" ) { rename("updown.cfg.tmp","updown.cfg"); }
        else { system("rename updown.cfg.tmp updown.cfg"); }
}

sub getconfig {
	# Get a variable value from the configuration file, or exit if a variable name was not found
        my $what = shift;
	my $error = 0;
        open(CF,"<","updown.cfg") or die "[getconfig] Unable to open
configuration file: $!\n";
        while(<CF>) {
                if ($_ =~ /^$what=/) { 
			chomp($_);
			close CF;
			return (split("=",$_))[-1];
		} else {
			next;
		}
        }
	if ($error > 0) {
		close CF;
		print "[getconfig] $what not found in the configuration file, exiting.\n";
	}
}

sub sendmail {
# Send a e-mail

	# Initialize new SMTP object
	my $smtp = new Net::SMTP::SSL(
	  getconfig("smtp-server"),
	  Port    =>      465,
	  Timeout  =>      10,
	  Debug   => 0,
	);

	# Initialize needed variables
	my $sender = getconfig("smtp-user");
	my $sender_name = 'updown.pl';
	my $reciever = getconfig("smtp-to");
	my $password = getconfig("smtp-password");
	my $subject = shift;
	my $body = shift;

	# Authenticate to the SMTP server
	$smtp->auth($sender,$password) or die "Could not authenticate:". $!;
	$smtp->mail($sender);
	$smtp->recipient($reciever);

	$smtp->data();
		 
	# -- This part creates the SMTP headers you see. --
	  $smtp->datasend("To: <$reciever> \n");
	  $smtp->datasend("From: $sender_name <$sender> \n");
	  $smtp->datasend("Content-Type: text/plain \n");
	  $smtp->datasend("Subject: $subject");
	 
	# -- line break to separate headers from message body. --
	  $smtp->datasend("\n");
	  $smtp->datasend($body);
	  $smtp->datasend("\n");
	  $smtp->dataend();
	  $smtp->quit;

}
