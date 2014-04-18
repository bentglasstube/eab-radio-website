package EaBRadio;

use AnyEvent;
use Dancer ':syntax';
use LWP::UserAgent;
use Net::MPD;

use utf8;
use strict;
use warnings;

our $VERSION = '0.1';

# TODO make dynamic
my $HOST = 'alan.radio.eatabrick.org';

my @hosts = (
  { host => 'alan.radio.eatabrick.org' },
  { host => 'steve.radio.eatabrick.org' },
);

our $timer = AnyEvent->timer(after => 1, interval => 10, cb => sub {
    debug 'Tick!';
    foreach my $host (@hosts) {
      unless ($host->{mpd}) {
        eval {
          $host->{mpd} = Net::MPD->connect($host->{host});
        };
        if ($@) {
          $host->{error} = $@;
          delete $host->{mpd};
        }
      }

      if ($host->{mpd}) {
        eval {
          $host->{mpd}->ping;
          $host->{status} = $host->{mpd}->update_status;
        };
        if ($@) {
          $host->{error} = $@;
          delete $host->{mpd};
        }
      }
    }
});

sub mpd {
  foreach my $host (@hosts) {
    return $host->{mpd} if $host->{mpd};
  }

  return undef;
}

get '/' => sub {
  template 'index';
};

get '/listen.*' => sub {
  my ($ext) = splat;
  redirect "http://$HOST:8000/radio.$ext";
};

get '/metadata' => sub {
  content_type 'application/json';
  to_json(mpd->current_song);
};

get '/playlist' => sub {
  content_type 'application/json';
  to_json([ mpd->playlist_info ]);
};

#cache for album art
my %_art = ();

get '/art' => sub {
  my $album = param('album');
  my $artist = param('artist');

  unless ($album and $artist) {
    my $info = mpd->current_song;
    $album = $info->{Album};
    $artist = $info->{Artist};
  }

  unless (exists $_art{$album, $artist}) {
    debug "Searching for art for $album, $artist";

    my $xml = LWP::UserAgent->new->post('http://ws.audioscrobbler.com/2.0', {
        method => 'album.getinfo',
        api_key => '4827e70daf0106ae5a88b268c083e65b',
        artist => $artist,
        album => $album,
      })->decoded_content;

    # TODO real xml parser
    my ($url) = $xml =~ m{<image size="small">(.*?)</image>};
    $url ||= '/unknown.png';

    $_art{$album, $artist} = $url;
  }

  header 'Cache-Control', 'no-cache, must-revalidate';
  redirect $_art{$album, $artist};
};

post '/skip' => sub {
  mpd->next;

  content_type 'application/json';
  to_json({ status => 'success' });
};

get '/hosts' => sub {
  template 'hosts', { hosts => \@hosts };
};

1;
