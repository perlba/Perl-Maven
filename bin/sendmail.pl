#!/usr/bin/perl
use strict;
use warnings;
use v5.12;

use Data::Dumper qw(Dumper);
use Getopt::Long qw(GetOptions);
use MIME::Lite;
use Cwd qw(abs_path cwd);
use File::Slurp    qw(read_file);
use WWW::Mechanize;
use DBI;
use YAML qw();

binmode(STDOUT, ':utf8');



my $dsn = "dbi:SQLite:dbname=pm.db";

my $dbh = DBI->connect($dsn, "", "", {
	RaiseError => 1,
	PrintError => 0,
	AutoCommit => 1,
});

my $config = YAML::LoadFile('config.yml');
my $mymaven = $config->{mymaven}{default};
my $from = $mymaven->{from};

my %opt;
GetOptions(\%opt,
	'to=s@',
	'url=s',
	'send',
) or usage();
usage() if not $opt{to} or not $opt{url};

my ($subject, %content) = build_content();
send_messages();
exit;
################################################################################

sub build_content {
	my $w = WWW::Mechanize->new;
	$w->get($opt{url});
	die 'missing title' if not $w->title;
	my $subject = $mymaven->{prefix} . ' ' . $w->title;

	my %content;
	my $utf8 = $w->content;
	$content{html} = $utf8;
	$content{text} = html2text($utf8);

	return $subject, %content;
}

sub send_messages {
    my %sent;
    my $count = 0;
    my $planned = 0;
    foreach my $to (@{$opt{to}}) {
	    if ($to =~ /\@/) {
            $planned++;
            next if $sent{$to};
		    sendmail($to);
            $count++;
            $sent{$to} = 1;
	    } else {
		    my $emails = $dbh->selectall_arrayref(q{
		        SELECT email
		        FROM user, subscription, product
		        WHERE user.id=subscription.uid
		          AND user.verify_time is not null
		          AND product.id=subscription.pid
		          AND product.code=?
		    }, undef, $to);
	#'perl_maven_cookbook'
	#die Dumper $emails;
		    my $total = scalar @$emails;
		    print "Sending to $total number of addresses\n";
		    next if not $opt{send};
		    foreach my $email (@$emails) {
                $planned++;
                my $address = $email->[0];
                next if $sent{$address};
			    $count++;
                $sent{$address} = 1;
			    say "$count out of $total to $address";
			    sendmail($address);
			    sleep 1;
            }
		}
	}
    say "Total sent $count. Planned: $planned";
	return;
}

sub sendmail {
	my $to = shift;

	my $msg = MIME::Lite->new(
		'From'     => $from,
		'To'       => $to,
		'Type'     => 'multipart/alternative',
		'Subject'  => $subject,
		);
	$msg->attr('List-Id'  => $mymaven->{listid}),

	my %type = (
		text => 'text/plain',
		html => 'text/html',
	);

	foreach my $t (qw(text html)) {
		my $att = MIME::Lite->new(
				Type     => 'text',
				Data     => $content{$t},
				Encoding => 'quoted-printable',
		);
		$att->attr("content-type" => "$type{$t}; charset=UTF-8");
		$att->replace("X-Mailer" => "");
		$att->attr('mime-version' => '');
		$att->attr('Content-Disposition' => '');

		$msg->attach($att);
	}
	$msg->send(smtp => 'localhost');

	return;
}

sub html2text {
	my $html = shift;

	$html =~ s{</?p>}{\n}gi;
	$html =~ s{<a href="([^"]+)">([^<]+)</a>}{$2 [ $1 ]}gi;

	$html =~ s{<[^>]+>}{}g;

	return $html;
}

sub usage {
	print <<"END_USAGE";
Usage: $0 --url http://url
    --send if I really want to send the messages

    --to mail\@address.com
#    --to all                      (all the subscribers) currently not supported

END_USAGE

	my $products = $dbh->selectall_arrayref(q{
	   SELECT code, name
	   FROM product
	});
	foreach my $p (@$products) {
		say "    --to $p->[0]";
	}
	exit;
}
