=head1 NAME

XML::SAXDriver::vCard - generate SAX events for vCard 3.0

=head1 SYNOPSIS

 use XML::SAX::Writer;
 use XML::SAXDriver::vCard;

 my $writer = XML::SAX::Writer->new();
 my $driver = XML::SAXDriver::vCard->new(Handler=>$writer);

 $driver->parse_file("test.vcd");

=head1 DESCRIPTION

Generate SAX events for vCard 3.0

=cut

use strict;

package XML::SAXDriver::vCard;
use base qw (XML::SAX::Base);

$XML::SAXDriver::vCard::VERSION = '0.02';

use constant NS => {
		    "VCARD" => "http://www.ietf.org/internet-drafts/draft-dawson-vCard-xml-dtd-04.txt",
		   };

use constant VCARD_VERSION => "3.0";

=head1 PACKAGE METHODS

=head2 __PACKAGE__->new(%args)

This method is inherited from I<XML::SAX::Base>

=cut

=head1 OBJECT METHODS

=head2 $pkg->parse($string)

=cut

sub parse {
  my $self = shift;
  my $str  = shift;

  if (! $str) {
    die "Nothing to parse.\n";
  }

  $self->start_document();
  $self->_parse_str($str);
  $self->end_document();

  return 1;
}

=head2 $pkg->parse_file($path)

=cut

sub parse_file {
  my $self  = shift;
  my $vcard = shift;

  $vcard =~ s/file:\/\///;

  require FileHandle;
  my $fh = FileHandle->new($vcard)
    || die "Can't open '$vcard', $!\n";

  $self->start_document();
  $self->_parse_file(\*$fh);
  $self->end_document();

  return 1;
}

=head2 $pkg->parse_uri($uri)

=cut

sub parse_uri {
  my $self = shift;
  my $uri  = shift;

  if ($uri =~ /^file:\/\//) {
    return $self->parse_file($uri);
  }

  require LWP::Simple;
  return $self->parse(LWP::Simple::get($uri));
}

# Private methods

sub _parse_str {
  my $self = shift;
  my $str  = shift;

  my %card = ();

  foreach (split("\n",$str)) {

    if (! $self->_parse_ln($_,\%card)) {
      %card = ();
    }
  }

  return 1;
}

sub _parse_file {
  my $self = shift;
  my $fh   = shift;

  my %card = ();

  while (! $fh->eof()) {
    my $ln = $fh->getline();
    chomp $ln;

    if (! $self->_parse_ln($ln,\%card)) {
      %card = ();
    }
  }

  return 1;
}

sub _parse_ln {
  my $self  = shift;
  my $ln    = shift;
  my $vcard = shift;

  # Danger, Will Robinson!
  # Un-SAX like behaviour ahead.Specifically, we are going to
  # store record data in a private hash ref belonging to the
  # object. I am not happy about this either, however we have to
  # do this because the vCard UID property is mapped to XML as
  # an attribute of the vcard element. Since we have no idea
  # where the UID property will be in the vCard -- it will probably
  # be near the bottom of the record -- we have to postpone any
  # writing until we get to it. There is always the possibility
  # that property won't be defined but... Anyway, there are other
  # properties that are mapped to vcard@foo so in an effort to keep
  # the code (relatively) small and clean I've opted for caching 
  # everything and writing it all out when the 'END:vCard thingy
  # is reached. It occured to me to write the (XML) data once, cache 
  # only a small set of properties and then add them at the end 
  # using XML::SAX::Merger. Ultimately, I decided that was crazy-talk.

  # These are the properties you are looking for.

  if ($ln =~ /^[DHIJQVWYZ]/) {
    return 1;
  }

  # AGENT properties are parsed separately when the current vCard
  # is rendered. So we'll just keep track of the agent's vcard data
  # as a big ol' string.

  elsif ($vcard->{'__isagent'}) {
    $vcard->{agent}{vcard} .= $ln."\n";
    if ($ln =~ /^EN/) { $vcard->{'__isagent'} = 0; }
    return 1;
  }

  else {}

  # FN
  if ($ln =~ /^F/) {
    $ln =~ /^FN:(.*)$/;
    $vcard->{fn} = $1;
  }

  # N
  elsif ($ln =~ /^N:/i) {
    # Family Name, Given Name, Additional Names, 
    # Honorific Prefixes, and Honorific Suffixes.
    $ln =~ /^N:([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?$/;
    $vcard->{n} = {family=>$1,given=>$2,other=>$3,prefixes=>$4,suffixes=>$5};
  }

  # NICKNAME
  elsif ($ln =~ /^NI/) {
    $ln =~ /^NICKNAME:(.*)$/;
    $vcard->{nickname} = $1;
  }

  # PHOTO
  elsif ($ln =~ /^PHOT/) {
    $ln =~ /^PHOTO;(?:VALUE=uri:(.*)|ENCODING=b;TYPE=([^:]+):(.*))$/;
    $vcard->{photo} = ($2) ? {type=>$1,b64=>$2} : {url=>$1};
  }

  # BDAY
  elsif ($ln =~ /^BD/) {
    $ln =~ /^BDAY:(.*)$/;
    $vcard->{bday} = $1;
  }

  # ADR
  if ($ln =~ /^AD/) {
    $ln =~ /^ADR;TYPE=([^:]+)?:([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?$/i;
    push @{$vcard->{adr}} , {"type"=>$1,pobox=>$2,extadr=>$3,street=>$4,locality=>$4,region=>$5,pcode=>$6,country=>$7};
  }

  # LABEL
  elsif ($ln =~ /^L/) {
  }

  # TEL
  elsif ($ln =~ /^TE/) {
    $ln =~ /^TEL;TYPE=([^:]+)?:(.*)$/;
    push @{$vcard->{tel}},{"type"=>$1,number=>$2};
  }

  # EMAIL
  elsif ($ln =~ /^EM/) {
    $ln =~ /^EMAIL;([^:]+)?:(.*)$/;
    push @{$vcard->{email}},{"type"=>$1,address=>$2};
  }

  # MAILER
  elsif ($ln =~ /^M/) {
    $ln =~ /^MAILER;(.*)$/;
    $vcard->{mailer} = $1;
  }

  # TZ
  elsif ($ln =~ /^TZ/) {
    $ln =~ /^TZ:(?:VALUE=([^:]+):)?(.*)$/;
    $vcard->{tz} = $1;
  }

  # GEO
  elsif ($ln =~ /^G/) {
    $ln =~ /^GEO:([^;]+);(.*)$/;
    $vcard->{geo} = {lat=>$1,lon=>$2};
  }

  # TITLE
  elsif ($ln =~ /^TI/) {
    $ln =~ /^TITLE:(.*)$/;
    $vcard->{title} = $1;
  }

  # ROLE
  elsif ($ln =~ /^R/) {
    $ln =~ /^ROLE:(.*)$/;
    $vcard->{role} = $1;
  }

  # LOGO
  elsif ($ln =~ /^L/) {
    $ln =~ /^LOGO;(?:VALUE=(.*)|ENCODING=b;TYPE=([^:]+):(.*))$/;
    $vcard->{logo} = ($2) ? {type=>$1,b64=>$2} : {url=>$1};
  }

  # AGENT
  elsif ($ln =~ /^AG/) {
    $ln =~ /^AGENT(;VALUE=uri)?:(.*)$/;

    if ($1) {
      $vcard->{agent}{'uri'} = $2;
    }

    $vcard->{'__isagent'}   = 1;

    # Note the '.='
    # It is possible that we are dealing
    # with nested AGENT properties. Ugh.
    $vcard->{agent}{vcard} .= "$2\n";
  }

  # ORG
  elsif ($ln =~ /^O/) {
    $ln =~ /^ORG:([^;]+);([^;]+);(.*)$/;
    $vcard->{org} = {name=>$1,unit=>$2};
  }

  # CATEGORIES
  elsif ($ln =~ /^CA/) {
    $ln =~ /^CATEGORIES:(.*)$/;
    $vcard->{categories} = [split(",",$1)];
  }

  # NOTE
  elsif ($ln =~ /^NO/) {
    $ln =~ /^NOTE:(.*)$/;
    $vcard->{note} = $1;
  }

  # PRODID
  elsif ($ln =~ /^PR/) {
    $ln =~ /^PRODID:(.*)$/;
    $vcard->{prodid} = $1;
  }

  # REV
  elsif ($ln =~ /^RE/) {
    $ln =~ /^REV:(.*)$/;
    $vcard->{rev} = $1;
  }

  # SORT-STRING
  elsif ($ln =~ /^SOR/) {
    $ln =~ /^SORT-STRING:(.*)/;
    $vcard->{'sort'} = $1;
  }

  # SOUND
  elsif ($ln =~ /^SOU/) {
    $ln =~ /^SOUND:TYPE=BASIC;(VALUE|ENCODING)=([buri]):(.*)$/;
    $vcard->{'sound'} = ($1 eq "VALUE") ? {uri=>$2} : {b64=>$2};
  }

  # UID
  elsif ($ln =~ /^UI/) {
    $ln =~ /^UID:(.*)$/;
    $vcard->{uid} = $1;
  }

  # URL
  elsif ($ln =~ /^UR/) {
    $ln =~ /^URL:(.*)$/;
    push @{$vcard->{url}},$1;
  }

  # CLASS
  elsif ($ln =~ /^CL/) {
    $ln =~ /^CLASS:(.*)$/;
    $vcard->{class} = $1;
  }

  # KEY
  elsif ($ln =~ /^K/) {
    $ln =~ /^KEY;ENCODING=b:(.*)$/;
    $vcard->{'key'} = $1;
  }

  # X-CUSTOM
  elsif ($ln =~ /^X/) {
    $ln =~ /^X-CUSTOM;([^:]+):(.*)$/;
    push @{$vcard->{'x-custom'}}, {$1=>$2};
  }

  # END:vCard
  elsif ($ln =~ /^EN/) {
    $self->_render_vcard($vcard);

    # We return 0 explicitly since that
    # is the signal to the calling method
    # that %$vcard should be emptied.
    return 0;
  }

  return 1
}

sub start_document {
  my $self = shift;

  $self->SUPER::start_document();
  $self->SUPER::xml_decl({Version=>"1.0"});
  # Add DOCTYPE stuff for X-LABEL here
  $self->start_prefix_mapping({Prefix=>"",NamespaceURI=>NS->{VCARD}});
  $self->SUPER::start_element({Name=>"vCardSet"});
  return 1;
}

sub end_document {
  my $self = shift;

  $self->SUPER::end_element({Name=>"vCardSet"});
  $self->end_prefix_mapping({Prefix=>""});
  $self->SUPER::end_document();
  return 1;
}

sub _render_vcard {
  my $self  = shift;
  my $vcard = shift;

  # See also : comments in &_parse()

  my $attrs = {
	       "{}version" => {Name=>"version",
			       Value=>VCARD_VERSION},
	       "{}class"=>{Name=>"class",
			   Value=>($vcard->{class} || "PUBLIC")},
	      };

  foreach ("uid","lang","rev","prodid") {
    if (exists($vcard->{$_})) {
      $attrs->{"{}$_"} = {Name=>$_,
			  Value=>$vcard->{$_}};
    }
  }

  #

  $self->SUPER::start_element({Name=>"vCard",Attributes=>$attrs});

  #

  # FN:
  $self->_pcdata({name=>"fn",value=>$vcard->{'fn'}});

  # N:
  $self->SUPER::start_element({Name=>"n"});

  foreach ("family","given","other","prefix","suffix") {
    $self->_pcdata({name=>$_,value=>$vcard->{'n'}{$_}});
  }

  $self->SUPER::end_element({Name=>"n"});

  # NICKNAME:
  if (exists($vcard->{'nickname'})) {
    $self->_pcdata({name=>"nickname",value=>$vcard->{'nickname'}});
  }

  # PHOTO:
  if (exists($vcard->{'photo'})) {
    $self->_media({name=>"photo",%{$vcard->{photo}}});
  }

  # BDAY:
  if (exists($vcard->{'bday'})) {
    $self->_pcdata({name=>"bday",value=>$vcard->{'bday'}});
  }

  # ADR:
  if (ref($vcard->{'adr'}) eq "ARRAY") {
    foreach my $adr (@{$vcard->{'adr'}}) {

      $self->SUPER::start_element({Name=>"adr",Attributes=>{"{}del.type"=>{Name=>"del.type",Value=>$adr->{type}}}});

      foreach ("pobox","extadr","street","locality","region","pcode","country") {
	$self->_pcdata({name=>$_,value=>$adr->{$_}});
      }

      $self->SUPER::end_element({Name=>"adr"});
    }
  }

  # LABEL
  # $self->label();

  if (ref($vcard->{'tel'}) eq "ARRAY") {
    foreach (@{$vcard->{'tel'}}) {
      $self->_pcdata({name=>"tel",value=>$_->{number},attrs=>{"{}tel.type"=>{Name=>"tel.type",Value=>$_->{type}}}});
    }
  }

  # EMAIL:
  if (ref($vcard->{'email'}) eq "ARRAY") {
    foreach (@{$vcard->{'email'}}) {
      $self->_pcdata({name=>"email",value=>$_->{address},attrs=>{"{}email.type"=>{Name=>"email.type",Value=>$_->{type}}}});
    }
  }

  # MAILER:
  if (exists($vcard->{'mailer'})) {
    $self->_pcdata({name=>"mailer",value=>$vcard->{'mailer'}});
  }

  # TZ:
  if (exists($vcard->{'tz'})) {
    $self->_pcdata({name=>"tz",value=>$vcard->{'tz'}});
  }

  # GEO:
  if (exists($vcard->{'geo'})) {
    $self->SUPER::start_element({Name=>"geo"});
    $self->_pcdata({name=>"lat",value=>$vcard->{'geo'}{'lat'}});
    $self->_pcdata({name=>"lon",value=>$vcard->{'geo'}{'lon'}});
    $self->SUPER::end_element({Name=>"geo"});
  }

  # TITLE:
  if (exists($vcard->{'title'})) {
    $self->_pcdata({name=>"title",value=>$vcard->{'title'}});
  }

  # ROLE
  if (exists($vcard->{'role'})) {
    $self->_pcdata({name=>"role",value=>$vcard->{'role'}});
  }

  # LOGO:
  if (exists($vcard->{'logo'})) {
    $self->_media({name=>"logo",%{$vcard->{'logo'}}});
  }

  # AGENT:
  if (exists($vcard->{agent})) {
    $self->SUPER::start_element({Name=>"agent"});

    if ($vcard->{agent}{uri}) {
      $self->_pcdata({name=>"extref",attrs=>{"{}uri"=>{Name=>"uri",
						       Value=>$vcard->{'agent'}{'uri'}}}
		     });
    }

    else {
      $self->_parse_str($vcard->{agent}{vcard});
    }

    $self->SUPER::end_element({Name=>"agent"});
  }

  # ORG:
  if (exists($vcard->{'org'})) {
    $self->SUPER::start_element({Name=>"org"});
    $self->_pcdata({name=>"orgnam",value=>$vcard->{'org'}{'name'}});
    $self->_pcdata({name=>"orgunit",value=>$vcard->{'org'}{'unit'}});
    $self->SUPER::end_element({Name=>"org"});
  }

  # CATEGORIES:
  if (ref($vcard->{'categories'}) eq "ARRAY") {
    $self->SUPER::start_element({Name=>"categories"});
    foreach (@{$vcard->{categories}}) {
      $self->_pcdata({name=>"item",value=>$_});
    }
    $self->SUPER::end_element({Name=>"categories"});
  }

  # NOTE:
  if (exists($vcard->{'note'})) {
    $self->_pcdata({name=>"note",value=>$vcard->{'note'}});
  }

  # SORT:
  if (exists($vcard->{'sort'})) {
    $self->_pcdata({name=>"sort",value=>$vcard->{'sort'}});
  }

  # SOUND:
  if (exists($vcard->{'sound'})) {
    $self->_media({name=>"sound",%{$vcard->{'sound'}}});
  }

  # URL:
  if (ref($vcard->{'url'}) eq "ARRAY") {
    foreach (@{$vcard->{'url'}}) {
      $self->_pcdata({name=>"url",Attributes=>{"{}uri"=>{Name=>"uri",Value=>$_}}});
    }
  }

  # KEY:
  if (exists($vcard->{'key'})) {
    $self->_media($vcard->{key});
  }

  # $self->xcustom();

  $self->SUPER::end_element({Name=>"vCard"});

  return 1;
}

sub _pcdata {
  my $self = shift;
  my $data = shift;
  $self->SUPER::start_element({Name=>$data->{name},Attributes=>$data->{attrs}});
  $self->SUPER::start_cdata() if ($data->{cdata});
  $self->SUPER::characters({Data=>$data->{value}});
  $self->SUPER::end_cdata() if ($data->{cdata});
  $self->SUPER::end_element({Name=>$data->{name}});
  return 1;
}

sub _media {
  my $self = shift;
  my $data = shift;

  my $attrs = {};

  # as in not 'key' and not something pointing to an 'uri'
  if ((! $data->{name} =~ /^k/) && ($data->{type})) {

    # as in 'photo' or 'logo' and not 'sound'
    my $mime = ($data->{name} =~ /^[pl]/i) ? "img" : "aud";
    $attrs = {"{}$mime.type"=>{Name=>"$mime.type",Value=>$data->{type}}};
  }

  $self->SUPER::start_element({Name=>$data->{name},Attributes=>$attrs});

  if ($data->{url}) {
     $self->_pcdata({name=>"extref",attrs=>{"{}uri"=>{Name=>"uri",
						      Value=>$data->{url}}}
		    });
  }

  else {
    $self->_pcdata({name=>"b64bin",value=>$data->{b64},cdata=>1});
  }

  $self->SUPER::end_element({Name=>$data->{name}});
  return 1;
}

sub _newkey {
  my $self = shift;
  my @keys = sort {$a<=>$b} keys %{$self->{'__vcards'}};
  return $keys[$#keys] + 1;
}

sub DESTROY {}

=head1 VERSION

0.02

=head1 DATE

November 05, 2002

=head1 AUTHOR

Aaron Straup Cope

=head1 TO DO

=over 4

=item *

Better (proper) support for properties that pan multiple lines

=item *

Better checks to prevent empty elements from being include in final
output.

=item *

Add support for I<LABEL> property

=item *

Add support for I<X-CUSTOM> properties. These are not actually defined 
in the vcard-xml DTD :-(

=item *

Add support for pronounciation attribute extension

=item *

RDF support. Maybe. If I'm bored, or something.

=back

=head1 SEE ALSO

http://www.ietf.org/rfc/rfc2426.txt

http://www.ietf.org/rfc/rfc2425.txt

http://www.globecom.net/ietf/draft/draft-dawson-vcard-xml-dtd-03.html

http://www.imc.org/pdi/vcard-pronunciation.html

=head1 BUGS

Sadly, there are probably a few.

Please report all bugs via http://rt.cpan.org

=head1 LICENSE

Copyright (c) 2002, Aaron Straup Cope. All Rights Reserved.

=cut

return 1;

