use strict;
use warnings;
use feature ':5.10';

use FindBin qw|$Bin|;
use lib "$Bin/lib";

use Carp;
use Data::Dumper;
use Encode;
use HTTP::Cookies;
use LWP::UserAgent;
use Mojo::DOM;
use MyLog;
use MyTools qw|rc slurp spew|;
#======= variables declare section ========
$ENV{HOME}=$Bin;
my %config;
rc($ENV{HOME}.'/pornolab.net.cfg', \%config);

my @tracker;
my $content;
my $base_url = 'http://pornolab.net/forum';
my %login = (
	login_username => $config{'username'},
	login_password => $config{'password'},
	ses_short      => '',
	login          => 'Вход');
my %tracker = (
	'f[]'    => $config{'category'},
	submit   => 'Поиск',
	nm       => '', o => 1,
	pn       => '', s => 2,
	tm       => -1,
	prev_my  => 0,
	prev_new => 0,
	prev_oop => 0);
my $log = MyLog->new({file => $config{'logs'}});
my $ua = LWP::UserAgent->new(
	agent      => 'Opera/9.80 (Windows NT 6.1; WOW64; U; en) Presto/2.10.289 Version/12.00',
	cookie_jar => HTTP::Cookies->new(
		file     => $config{'cookies'},
		autosave => 1)
	);
#======= main section ========
$Data::Dumper::Terse = 1;
$log->info('-Script Start-');
$log->debug("\$ENV{HOME}: $ENV{HOME}");
mkdir $config{'out'} unless -d $config{'out'};

ua_get(\$ua, $base_url.'/tracker.php', \$content);
unless(is_in( Mojo::DOM->new($content)->at('.topmenu') )){
	say 'Login';
	ua_post(\$ua, $base_url.'/login.php', \%login, \$content);
	ua_get(\$ua, $base_url.'/tracker.php', \$content);
}
if(@ARGV){
	$ARGV[0] =~ s;^.+/;;;
	parse_topic(\$ua, \$content, {link => $ARGV[0], name => 'Custom', date => time});
	exit;
}

say 'Get tracker';
unless(-f $config{'tracker'}){
	$config{'exclude'} = [ map {qr/\Q$_\E/i} split/,\s*/, $config{'exclude'} ];
	if(-f $config{'tracker_html'}){
		$log->info('Local tracker list founded.');
		$content = slurp(":$config{'tracker_html'}");
		unlink $config{'tracker_html'} or die "Can't delete file [$config{'tracker_html'}]: $!";
	}else{
		ua_post(\$ua, $base_url.'/tracker.php', \%tracker, \$content);
	}
	for my $tr (Mojo::DOM->new($content)->at('#tor-tbl')->tbody->tr->each){
		my ($link, $name, $size, $date) = ($tr->td->[3]->div->a->{'href'}, $tr->td->[3]->div->a->content_xml, $tr->td->[5]->u->text, $tr->td->[9]->u->text);
		$name = get_clean_name($name);
		next if grep{$name eq $_->{'name'}} @tracker or grep{$name =~ $_} @{$config{'exclude'}};
		$link =~ s;^\./;;;
		push @tracker, {id => $link =~ /=(\d+)$/, link => $link, name => $name, size => $size, date => $date};
	}
}else{
	@tracker = @{do $config{'tracker'}};
}
my $last_topic = do $config{'last_topic'};
while(@tracker){
	spew($config{'tracker'}, Dumper(\@tracker));
	
	my $topic = pop @tracker;
	$log->info('TOPIC: '.$topic->{'name'});
	next if $last_topic > $topic->{'date'};
	say '#'.scalar(@tracker).' '.$topic->{'name'};
	
	parse_topic(\$ua, \$content, $topic);
	
	spew($config{'last_topic'}, $topic->{'date'});
}

unlink $config{'tracker'} or die "Can't delete file [$config{'tracker'}]: $!";
say 'Done';
#======= subroutines declare section ========
sub ua_get{
	my ($user_agent, $url, $content) = @_;
	
	$log->info("GET: $url");
	my $response = $$user_agent->get($url);
	
	$log->info('RESPONSE: '.$response->status_line);
	croak 'Response returned error: '.$response->status_line if $response->is_error;
	
	$$content = encode('cp1251', $response->decoded_content);
}
sub ua_post{
	my ($user_agent, $url, $form, $content) = @_;
	
	$log->info("POST: $url");
	my $response = $$user_agent->post($url, $form);
	
	$log->info('RESPONSE: '.$response->status_line);
	croak 'Response returned error: '.$response->status_line if $response->is_error;
	
	$$content = encode('cp1251', $response->decoded_content);
}
sub ua_save{
	my ($user_agent, $url, $name) = @_;
	
	$log->info("SAVE: $url");
	my $response = $$user_agent->get($url);
	
	$log->info('RESPONSE: '.$response->status_line);
	croak 'Response returned error: '.$response->status_line unless $response->is_success;
	
	spew(':'.$config{'out'}."/$name", $response->content);
	$log->info('SAVED: '.$config{'out'}."/$name");
}
sub parse_topic{
	my ($user_agent, $content, $topic) = @_;
	
	ua_get($user_agent, $base_url.'/'.$topic->{'link'}, $content);
	
	my $dom = Mojo::DOM->new($$content)->at('#topic_main');
	$log->info("SKIPPED: No topic"), return unless $dom;
	$dom = $dom->children('tbody')->[0]->at('div.post_wrap > div.post_body');
	$dom->at('div.#tor-reged')->replace('<div></div>');
	
	$topic->{'name'} = dt($topic->{'date'}).' '.$topic->{'name'};
	for my $div ($dom->children('div')->each){
		get_images($user_agent, $topic->{'name'}, $div->div) if exists $div->{'class'} && $div->{'class'} eq 'sp-wrap';
	}
	spew( $config{'out'}.'/'.$topic->{'name'}.'.txt', join("\r\n", $base_url.'/'.$topic->{'link'}, Dumper($topic)) );
}
sub get_images{
	my ($user_agent, $name, $dom) = @_;
	
	$log->debug('DIV: '.($dom->{'title'}||''));
	$name .= ' @ '.get_clean_name($dom->{'title'});
	
	for my $div ($dom->children('div')->each){
		if(exists $div->{'class'} && $div->{'class'} eq 'sp-wrap'){
			$log->debug('SubDIV: '.$div->div->{'title'});
			get_images($user_agent, $name, $div->div);
		}
	}
	
	$dom = $_ while $_ = $dom->children('span')->grep(sub {$_->{'class'} eq 'post-align'})->first;
	my $n = 1;
	my @vars = ($dom->children('a')->map(sub{$_->children('var')->each})->each, $dom->children('var')->each);
	$log->info('Too many limks. Checking first and last.'), @vars = @vars[0,-1] if @vars > $config{'max_img'};
	
	for my $var (@vars){
		next unless my ($img_url, $file) = get_img_address($user_agent, $name.' #'.$n, $var->{'title'}, $var->parent->{'href'});
		$n++;
		$log->info("SKIPPED: File already exists - $file"), next if -f $config{'out'}."/$file";
		ua_save($user_agent, $img_url, $file)
	}
}
sub get_img_address{
	my ($user_agent, $name, $title, $href) = @_;
	
	$log->debug("IMGADDR: $title");
	
	given($title){
		when(/fastpic\.ru/){
			if($title =~ s;/thumb/;/big/;){
				($href) = $href =~ m;\.(\w+).\w+$;;
				$title =~ s;jpeg$;$href;;
			}
			$name .= $1 if $title =~ m;(\.\w+)$;;
			return ($title, $name);
		}
		when(/imagevenue\.com/){
			die 'TODO: imagevenue.com' unless $title =~ m;lo\.\w+$;;
			$name .= $1 if $title =~ m;(\.\w+)$;;
			$title =~ s;/[^/]+/th_;/img\.php?image=;;
			ua_get($user_agent, $title, \my $content);
			$content = Mojo::DOM->new($content)->at('img#thepic')->{'src'};
			$title =~ s;/img\.php.+$;/$content;;
			return ($title, $name);
		}
		when(/imagebam\.com/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			$title =~ s;^.+/([^/]+)\.\w+$;http://www.imagebam.com/image/$1;;
			ua_get($user_agent, $title, \my $content);
			$title = Mojo::DOM->new($content)->at('div#imageContainer')->table->tr->[1]->td->img->{'src'};
			return ($title, $name);
		}
		when(/linkpic\.ru/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			$href =~ s;^.+/([^/]+)\.html$;$1;;
			$title =~ s;/[^/]+$;/$href;;
			return ($title, $name);
		}
		when(/image2you\.ru/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			substr $title, rindex($title, '/')+1, 2, '';
			return ($title, $name);
		}
		when(/pix-x\.net/ || /piccash\.net/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			$title =~ s;-thumb;;;$title =~ s;thumb;full;;
			return ($title, $name);
		}
		when(/pic5you\.ru/ || /megaimg\.ru/ || /stuffed\.ru/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			$title =~ s;-thumb;;;
			return ($title, $name);
		}
		when(/10pix\.ru/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			$title =~ s;\.th;;;
			return ($title, $name);
		}
		when(/batpic\.com/){
			$name .= $1 if $title =~ m;(\.\w+)$;;
			return ($title, $name);
		}
		default{die 'Unknown image hosting '.$title}
	}
	return;
}
sub is_in{
	my ($dom) = @_;
	return 0 if $dom->at('form');
	return 1;
}
sub get_clean_name{
	my ($string) = @_;
	
	return '' unless $string;
	
	($string) = map{s;<wbr />;;ig;s/&#\d+;/ /g;y;\\/:*?"<>|;;d;s;\[\d+p\];;;s;\[[^\[]+$;;g;s/&amp;/&/ig;s;\s+; ;g;s;\s+$;;g;substr $_, 0, 130} $string;
	
	return $string;
}
sub dt{
	my ($time) = @_;
	
	my ($min, $hour, $day, $mon, $year) = (localtime($time))[1..5];
	$mon++;$year += 1900;
	
	return sprintf('%d-%02d-%02d_%02d%02d', $year, $mon, $day, $hour, $min);
}