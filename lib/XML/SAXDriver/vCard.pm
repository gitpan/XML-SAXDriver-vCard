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

$XML::SAXDriver::vCard::VERSION = '0.01';

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

  foreach (split("\n",$str)) {
    my $ln = $_;
    chomp $ln;
    $self->_parse($ln);
  }

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

  while (! $fh->eof()) {
    my $ln = $fh->getline();
    chomp $ln;
    $self->_parse($ln);
  }

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


sub end_document {
  my $self = shift;
  return 1;
}

# Private methods

sub _parse {
  my $self = shift;
  my $ln   = shift;

  # These are the properties you are looking for.

  if ($ln =~ /^[DHIJQVWYZ]/) {
    return;
  }

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

  # FN
  elsif ($ln =~ /^F/) {
    $ln =~ /^FN:(.*)$/;
    $self->{'__vcard'}{fn} = $1;
  }

  # N
  elsif ($ln =~ /^N:/i) {
    # Family Name, Given Name, Additional Names, 
    # Honorific Prefixes, and Honorific Suffixes.
    $ln =~ /^N:([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?$/;
    $self->{'__vcard'}{n} = {family=>$1,given=>$2,other=>$3,prefixes=>$4,suffixes=>$5};
  }

  # NICKNAME
  elsif ($ln =~ /^NI/) {
    $ln =~ /^NICKNAME:(.*)$/;
    $self->{'__vcard'}{nickname} = $1;
  }

  # PHOTO
  elsif ($ln =~ /^PHOT/) {
    $ln =~ /^PHOTO;(?:VALUE=uri:(.*)|ENCODING=b;TYPE=([^:]+):(.*))$/;
    $self->{'__vcard'}{photo} = ($2) ? {type=>$1,b64=>$2} : {url=>$1};
  }

  # BDAY
  elsif ($ln =~ /^BD/) {
    $ln =~ /^BDAY:(.*)$/;
    $self->{'__vcard'}{bday} = $1;
  }

  # ADR
  if ($ln =~ /^AD/) {
    $ln =~ /^ADR;TYPE=([^:]+)?:([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?;([^;]+)?$/i;
    push @{$self->{'__vcard'}{adr}} , {"type"=>$1,pobox=>$2,extadr=>$3,street=>$4,locality=>$4,region=>$5,pcode=>$6,country=>$7};
  }

  # LABEL
  elsif ($ln =~ /^L/) {
  }

  # TEL
  elsif ($ln =~ /^TE/) {
    $ln =~ /^TEL;TYPE=([^:]+)?:(.*)$/;
    push @{$self->{'__vcard'}{tel}},{"type"=>$1,number=>$2};
  }

  # EMAIL
  elsif ($ln =~ /^EM/) {
    $ln =~ /^EMAIL;([^:]+)?:(.*)$/;
    push @{$self->{'__vcard'}{email}},{"type"=>$1,address=>$2};
  }

  # MAILER
  elsif ($ln =~ /^M/) {
    $ln =~ /^MAILER;(.*)$/;
    $self->{'__vcard'}{mailer} = $1;
  }

  # TZ
  elsif ($ln =~ /^TZ/) {
    $ln =~ /^TZ:(?:VALUE=([^:]+):)?(.*)$/;
    $self->{'__vcard'}{tz} = $1;
  }

  # GEO
  elsif ($ln =~ /^G/) {
    $ln =~ /^GEO:([^;]+);(.*)$/;
    $self->{'__vcard'}{geo} = {lat=>$1,lon=>$2};
  }

  # TITLE
  elsif ($ln =~ /^TI/) {
    $ln =~ /^TITLE:(.*)$/;
    $self->{'__vcard'}{title} = $1;
  }

  # ROLE
  elsif ($ln =~ /^R/) {
    $ln =~ /^ROLE:(.*)$/;
    $self->{'__vcard'}{role} = $1;
  }

  # LOGO
  elsif ($ln =~ /^L/) {
    $ln =~ /^LOGO;(?:VALUE=(.*)|ENCODING=b;TYPE=([^:]+):(.*))$/;
    $self->{'__vcard'}{logo} = ($2) ? {type=>$1,b64=>$2} : {url=>$1};
  }

  # AGENT
  elsif ($ln =~ /^AG/) {
  }

  # ORG
  elsif ($ln =~ /^O/) {
    $ln =~ /^ORG:([^;]+);([^;]+);(.*)$/;
    $self->{'__vcard'}{org} = {name=>$1,unit=>$2};
  }

  # CATEGORIES
  elsif ($ln =~ /^CA/) {
    $ln =~ /^CATEGORIES:(.*)$/;
    $self->{'__vcard'}{categories} = [split(",",$1)];
  }

  # NOTE
  elsif ($ln =~ /^NO/) {
    $ln =~ /^NOTE:(.*)$/;
    $self->{'__vcard'}{note} = $1;
  }

  # PRODID
  elsif ($ln =~ /^PR/) {
    $ln =~ /^PRODID:(.*)$/;
    $self->{'__vcard'}{prodid} = $1;
  }

  # REV
  elsif ($ln =~ /^RE/) {
    $ln =~ /^REV:(.*)$/;
    $self->{'__vcard'}{rev} = $1;
  }

  # SORT-STRING
  elsif ($ln =~ /^SOR/) {
    $ln =~ /^SORT-STRING:(.*)/;
    $self->{'__vcard'}{'sort'} = $1;
  }

  # SOUND
  elsif ($ln =~ /^SOU/) {
    $ln =~ /^SOUND:TYPE=BASIC;(VALUE|ENCODING)=([buri]):(.*)$/;
    $self->{'__vcard'}{'sound'} = ($1 eq "VALUE") ? {uri=>$2} : {b64=>$2};
  }

  # UID
  elsif ($ln =~ /^UI/) {
    $ln =~ /^UID:(.*)$/;
    $self->{'__vcard'}{uid} = $1;
  }

  # URL
  elsif ($ln =~ /^UR/) {
    $ln =~ /^URL:(.*)$/;
    push @{$self->{'__vcard'}{url}},$1;
  }

  # CLASS
  elsif ($ln =~ /^CL/) {
    $ln =~ /^CLASS:(.*)$/;
    $self->{'__vcard'}{class} = $1;
  }

  # KEY
  elsif ($ln =~ /^K/) {
    $ln =~ /^KEY;ENCODING=b:(.*)$/;
    $self->{'__vcard'}{'key'} = $1;
  }

  # X-CUSTOM
  elsif ($ln =~ /^X/) {
    $ln =~ /^X-CUSTOM;([^:]+):(.*)$/;
    push @{$self->{'__vcard'}{'x-custom'}}, {$1=>$2};
  }

  # END:vCard
  elsif ($ln =~ /^EN/) {
    $self->_vcard();
  }

  return 1;
}

sub _vcard {
  my $self = shift;

  # See also : comments in &_parse()

  my $attrs = {
	       "{}version" => {Name=>"version",
			       Value=>VCARD_VERSION},
	       "{}class"=>{Name=>"class",
			   Value=>($self->{'__vcard'}->{class} || "PUBLIC")},
	      };

  foreach ("uid","lang","rev","prodid") {
    if (exists($self->{'__vcard'}->{$_})) {
      $attrs->{"{}$_"} = {Name=>$_,
			  Value=>$self->{'__vcard'}->{$_}};
    }
  }

  #

  $self->SUPER::start_document();
  $self->SUPER::xml_decl({Version=>"1.0"});

  $self->start_prefix_mapping({Prefix=>"",NamespaceURI=>NS->{VCARD}});
  $self->SUPER::start_element({Name=>"vCardSet"});
  $self->SUPER::start_element({Name=>"vCard",Attributes=>$attrs});

  #

  # FN:
  $self->_pcdata({name=>"fn",value=>$self->{'__vcard'}{'fn'}});

  # N:
  $self->SUPER::start_element({Name=>"n"});

  foreach ("family","given","other","prefix","suffix") {
    $self->_pcdata({name=>$_,value=>$self->{'__vcard'}{'n'}{$_}});
  }

  $self->SUPER::end_element({Name=>"n"});

  # NICKNAME:
  if (exists($self->{'__vcard'}{'nickname'})) {
    $self->_pcdata({name=>"nickname",value=>$self->{'__vcard'}{'nickname'}});
  }

  # PHOTO:
  if (exists($self->{'__vcard'}{'photo'})) {
    $self->_media({name=>"photo",%{$self->{'__vcard'}{photo}}});
  }

  # BDAY:
  if (exists($self->{'__vcard'}{'bday'})) {
    $self->_pcdata({name=>"bday",value=>$self->{'__vcard'}{'bday'}});
  }

  # ADR:
  if (ref($self->{'__vcard'}{'adr'}) eq "ARRAY") {
    foreach my $adr (@{$self->{'__vcard'}{'adr'}}) {

      $self->SUPER::start_element({Name=>"adr",Attributes=>{"{}del.type"=>{Name=>"del.type",Value=>$adr->{type}}}});

      foreach ("pobox","extadr","street","locality","region","pcode","country") {
	$self->_pcdata({name=>$_,value=>$adr->{$_}});
      }

      $self->SUPER::end_element({Name=>"adr"});
    }
  }

  # LABEL
  # $self->label();

  if (ref($self->{'__vcard'}{'tel'}) eq "ARRAY") {
    foreach (@{$self->{'__vcard'}{'tel'}}) {
      $self->_pcdata({name=>"tel",value=>$_->{number},attrs=>{"{}tel.type"=>{Name=>"tel.type",Value=>$_->{type}}}});
    }
  }

  # EMAIL:
  if (ref($self->{'__vcard'}{'email'}) eq "ARRAY") {
    foreach (@{$self->{'__vcard'}{'email'}}) {
      $self->_pcdata({name=>"email",value=>$_->{address},attrs=>{"{}email.type"=>{Name=>"email.type",Value=>$_->{type}}}});
    }
  }

  # MAILER:
  if (exists($self->{'__vcard'}{'mailer'})) {
    $self->_pcdata({name=>"mailer",value=>$self->{'__vcard'}{'mailer'}});
  }

  # TZ:
  if (exists($self->{'__vcard'}{'tz'})) {
    $self->_pcdata({name=>"tz",value=>$self->{'__vcard'}{'tz'}});
  }

  # GEO:
  if (exists($self->{'__vcard'}{'geo'})) {
    $self->SUPER::start_element({Name=>"geo"});
    $self->_pcdata({name=>"lat",value=>$self->{'__vcard'}{'geo'}{'lat'}});
    $self->_pcdata({name=>"lon",value=>$self->{'__vcard'}{'geo'}{'lon'}});
    $self->SUPER::end_element({Name=>"geo"});
  }

  # TITLE:
  if (exists($self->{'__vcard'}{'title'})) {
    $self->_pcdata({name=>"title",value=>$self->{'__vcard'}{'title'}});
  }

  # ROLE
  if (exists($self->{'__vcard'}{'role'})) {
    $self->_pcdata({name=>"role",value=>$self->{'__vcard'}{'role'}});
  }

  # LOGO:
  if (exists($self->{'__vcard'}{'logo'})) {
    $self->_media({name=>"logo",%{$self->{'__vcard'}{'logo'}}});
  }

  # AGENT:
  # $self->agent();

  # ORG:
  if (exists($self->{'__vcard'}{'org'})) {
    $self->SUPER::start_element({Name=>"org"});
    $self->_pcdata({name=>"orgnam",value=>$self->{'__vcard'}{'org'}{'name'}});
    $self->_pcdata({name=>"orgunit",value=>$self->{'__vcard'}{'org'}{'unit'}});
    $self->SUPER::end_element({Name=>"org"});
  }

  # CATEGORIES:
  if (ref($self->{'__vcard'}{'categories'}) eq "ARRAY") {
    $self->SUPER::start_element({Name=>"categories"});
    foreach (@{$self->{'__vcard'}{categories}}) {
      $self->_pcdata({name=>"item",value=>$_});
    }
    $self->SUPER::end_element({Name=>"categories"});
  }

  # NOTE:
  if (exists($self->{'__vcard'}{'note'})) {
    $self->_pcdata({name=>"note",value=>$self->{'__vcard'}{'note'}});
  }

  # SORT:
  if (exists($self->{'__vcard'}{'sort'})) {
    $self->_pcdata({name=>"sort",value=>$self->{'__vcard'}{'sort'}});
  }

  # SOUND:
  if (exists($self->{'__vcard'}{'sound'})) {
    $self->_media({name=>"sound",%{$self->{'__vcard'}{'sound'}}});
  }

  # URL:
  if (ref($self->{'__vcard'}{'url'}) eq "ARRAY") {
    foreach (@{$self->{'__vcard'}{'url'}}) {
      $self->_pcdata({name=>"url",Attributes=>{"{}uri"=>{Name=>"uri",Value=>$_}}});
    }
  }

  # KEY:
  if (exists($self->{'__vcard'}{'key'})) {
    $self->_media($self->{'__vcard'}{key});
  }

  # $self->xcustom();

  $self->SUPER::end_element({Name=>"vCard"});
  $self->SUPER::end_element({Name=>"vCardSet"});
  $self->end_prefix_mapping({Prefix=>""});

  $self->SUPER::end_document();

  $self->{'__vcard'} = {};
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
     $self->_pcdata({name=>"extref",value=>$data->{url}});
  }

  else {
    $self->_pcdata({name=>"b64bin",value=>$data->{b64},cdata=>1});
  }

  $self->SUPER::end_element({Name=>$data->{name}});
  return 1;
}

sub DESTROY {}

=head1 VERSION

0.01

=head1 DATE

November 04, 2002

=head1 AUTHOR

Aaron Straup Cope

=head1 TO DO

=over 4

=item *

Add support for I<AGENT> property

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

