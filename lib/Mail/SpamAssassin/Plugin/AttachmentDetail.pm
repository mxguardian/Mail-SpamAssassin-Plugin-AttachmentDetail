# <@LICENSE>
# Licensed under the Apache License 2.0. You may not use this file except in 
# compliance with the License.  You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# </@LICENSE>

=head1 NAME

Mail::SpamAssassin::Plugin::AttachmentDetail - SpamAssassin plugin to check attachment details

=head1 DESCRIPTION

This plugin creates a new rule test type, called "attachment".  These
rules apply to all attachments found in the message. Any MIME part
that has a filename is considered an "attachment" regardless of the content
disposition.

=head1 SYNOPSIS

  loadplugin    Mail::SpamAssassin::Plugin::AttachmentDetail

  attachment    INVALID_HTML_TYPE       name =~ /\.s?html?/i type != text/html
  attachment    GEEKSQUAD_IMAGE_SPAM    name =~ /^geek/i type =~ /^image\//
  attachment    TRAILING_DOT            name =~ /\.$/
  attachment    DOUBLE_EXTENSION        name =~ /\.[^.\/\s]{2,4}\.[^.\/\s]{2,4}$/i
  ...

  body          __ATTACH_NONE             eval:check_attachment_count(0,0)
  body          __ATTACH_SINGLE           eval:check_attachment_count(1,1)
  body          __ATTACH_MULTI            eval:check_attachment_count(2,9999)

This plugin also creates the following eval rule:

 body RULENAME  eval:check_attachment_count(<min>, <max>)
    min: minimum number of attachments
    max: maximum number of attachments

    Returns true if the number of attachments is between min and max (inclusive).

=head1 FAQ

Q: Can't I just use a C<mimeheader> rule to check attachment details? For example, I already have this rule to
look for HTML attachments with the wrong MIME type:

    mimeheader  OBFU_HTML_ATTACH   Content-Type =~ m,\bapplication/octet-stream\b.+\.s?html?\b,i

A: There's a few problems with this approach. First, the filename is not always included in the Content-Type header.
It can be included in the Content-Disposition header instead. For example:

    Content-Type: application/octet-stream;
    Content-Disposition: attachment; filename="document.html"

Second, the filename can be encoded and split across multiple lines using Parameter Value Continuation. For example:

    Content-Type: application/octet-stream;
        name*0*=UTF-8''%64%6F%63%75%6D%65%6E
        name*1*=%74%2E%68%74%6D%6C

As of SA version 4.0.0, the C<mimeheader> rule does not properly decode Parameter Value Continuation. This plugin does.
For more information on Parameter Value Continuation, see RFC 2231. L<https://datatracker.ietf.org/doc/html/rfc2231>

Third, it's easy to make mistakes when writing regular expressions. For example, the above rule will match
any filename that contains the string ".html" such as "document.html.zip" which may or may not be
what you want. This plugin simplifies the process of writing rules for attachments, leading to fewer mistakes.

=head1 RULE DEFINITIONS

The format for defining a rule is as follows:

  attachment SYMBOLIC_TEST_NAME key1 =~ /value1/i  key2 == value2 ...

Supported keys are:

C<name> is the suggested filename as specified in the Content-Type header

C<ext> is the file extension (e.g. html, pdf, docx, etc.) as determined from the filename

C<type> is the attachment MIME type (e.g. image/png, application/pdf, etc.)

C<disposition> is the content disposition (e.g. attachment or inline)

C<encoding> is the content transfer encoding (e.g. 7bit, base64, quoted-printable, etc.)

C<charset> is the character set (e.g. us-ascii, UTF-8, Windows-1251, ISO-8859-1, etc.)

Supported operators are:

C<==> equal to

C<!=> not equal to

C<=~> matches regular expression

C<!~> does not match regular expression

Regular expressions should be delimited by slashes and can optionally include modifiers after the terminating slash.
Text values may be enclosed in single or double quotes. Quotes may be omitted as long as the text does not
contain any spaces.

If more than one condition is specified on a single rule, then ALL conditions must be true for the test to hit
(i.e. logical AND).

=head1 TAGS

This plugin adds the following tags:

C<ATTACHMENT_COUNT> is the number of attachments found in the message

C<ATTACHMENT_TYPES> is a comma-separated list of all the MIME types found in the message

C<ATTACHMENT_EXTS> is a comma-separated list of all the file extensions found in the message

You can add custom headers to the message by adding the following to your local.cf:

    add_header all Attachment-Count _ATTACHMENT_COUNT_
    add_header all Attachment-Types _ATTACHMENT_TYPES_
    add_header all Attachment-Exts _ATTACHMENT_EXTS_

This will add headers to the message like this:

    X-Spam-Attachment-Count: 2
    X-Spam-Attachment-Types: image/png, application/pdf
    X-Spam-Attachment-Exts: png, pdf

=head1 ACKNOWLEDGEMENTS

This plugin was modeled after the URIDetail plugin

=head1 REQUIREMENTS

Email::MIME::ContentType 1.022 or later

=head1 AUTHORS

Kent Oyer <kent@mxguardian.net>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023 MXGuardian LLC

This is free software; you can redistribute it and/or modify it under
the terms of the Apache License 2.0. See the LICENSE file included
with this distribution for more information.

This plugin is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

package Mail::SpamAssassin::Plugin::AttachmentDetail;
use strict;
use warnings FATAL => 'all';
use v5.12;

our $VERSION = 0.06;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger;
use Mail::SpamAssassin::Util qw(compile_regexp);
use Email::MIME::ContentType;

our @ISA = qw(Mail::SpamAssassin::Plugin);

# constructor
sub new {
    my $class = shift;
    my $mailsaobject = shift;

    # some boilerplate...
    $class = ref($class) || $class;
    my $self = $class->SUPER::new($mailsaobject);
    bless ($self, $class);

    $self->register_eval_rule("check_attachment_detail");
    $self->register_eval_rule("check_attachment_count");

    # other plugins may rely on us, so we need to run first
    $self->register_method_priority("parsed_metadata", -10);

    $self->set_config($mailsaobject->{conf});

    return $self;
}

sub set_config {
    my ($self, $conf) = @_;
    my @cmds;

    push (@cmds, {
        setting => 'attachment',
        is_priv => 1,
        code => sub {
            my ($self, $key, $value, $line) = @_;

            if ($value !~ /^(\S+)\s+(.+)$/) {
                return $Mail::SpamAssassin::Conf::INVALID_VALUE;
            }
            my $name = $1;
            my $def = $2;
            my $added_criteria = 0;

            while ($def =~ m{\b(\w+)\b\s*([\=\!][\~\=])\s*((?:\/.*?\/|m(\W).*?\4)[imsx]*|(["']).*?\5|[^\s"']+)(?=\s|$)}g) {
                my $target = $1;
                my $op = $2;
                my $pattern = $3;

                if ($target !~ /^(?:name|type|disposition|encoding|charset|ext)$/) {
                    return $Mail::SpamAssassin::Conf::INVALID_VALUE;
                }

                if ( $op =~ /~/ ) {
                    my ($re, $err) = compile_regexp($pattern, 1);
                    if (!$re) {
                        dbg("config: attachment_detail invalid regexp '$pattern': $err");
                        return $Mail::SpamAssassin::Conf::INVALID_VALUE;
                    }
                    $pattern = $re;
                } else {
                    $pattern =~ s/^["']|["']$//g;   # strip quotes
                }

                dbg("config: attachment_detail adding ($target $op $pattern) to $name");
                $conf->{parser}->{conf}->{attachment_detail}->{$name}->{$target} =
                    [$op, $pattern];

                $added_criteria = 1;
            }

            if ($added_criteria) {
                dbg("config: attachment_detail added $name\n");
                $conf->{parser}->add_test($name, 'check_attachment_detail()',
                    $Mail::SpamAssassin::Conf::TYPE_BODY_EVALS);
            } else {
                warn "config: attachment_detail failed to add invalid rule $name";
                return $Mail::SpamAssassin::Conf::INVALID_VALUE;
            }
        }
    });

    $conf->{parser}->register_commands(\@cmds);
}

sub parsed_metadata {
    my ($self, $opts) = @_;
    #@type Mail::SpamAssassin::PerMsgStatus
    my $pms = $opts->{permsgstatus};
    #@type Mail::SpamAssassin::Message
    my $msg = $pms->{msg};
    #@type Mail::SpamAssassin::Message::Node
    my $p;

    local $Email::MIME::ContentType::STRICT_PARAMS = 0;

    # gather info on attachments
    $pms->{'attachments'} = [];
    my (%extensions, %types);
    foreach $p ($msg->find_parts(qr/./, 0)) {

        my $cd = $p->get_header('content-disposition');
        next unless defined($cd);

        eval {
            $cd = parse_content_disposition($cd);

            my $ct = $p->get_header('content-type');
            die "Content-Type header missing\n" unless defined($ct);
            $ct = parse_content_type($ct);

            my $name = $cd->{attributes}->{filename} || $ct->{attributes}->{name};
            if ( defined($name) || $cd->{type} eq 'attachment' ) {
                $name ||= '';
                my $ext = $name =~ /\.(\w+)$/ ? lc($1) : '';
                my $cte = $p->get_header('content-transfer-encoding') || '';
                chomp $cte;

                my $type = $ct->{type}.'/'.$ct->{subtype};
                my $effective_type = $name =~ /\.s?html?$/i ? 'text/html' : $type;

                push @{$pms->{'attachments'}}, {
                    'type'           => $type,
                    'effective_type' => $effective_type,
                    'name'           => $name,
                    'ext'            => $ext,
                    'encoding'       => $cte,
                    'charset'        => $ct->{attributes}->{charset},
                    'disposition'    => $cd->{type},
                    'part'           => $p,
                };

                $extensions{$ext}++ if $ext;
                $types{$type}++;

            }
            1;
        } or do {
            my $err = $@;
            chomp $err;
            warn "attachment_detail: error parsing attachment: $err";
        };

    }
    dbg("attachment_detail: found %d attachments", scalar @{$pms->{'attachments'}});

    $pms->set_tag('ATTACHMENT_COUNT', scalar @{$pms->{'attachments'}});
    $pms->set_tag('ATTACHMENT_TYPES', join(',', keys %types));
    $pms->set_tag('ATTACHMENT_EXTS', join(',', keys %extensions));

}

sub check_attachment_detail {
    my ($self, $permsg) = @_;

    my $test = $permsg->{current_rule_name};
    my $rule = $permsg->{conf}->{attachment_detail}->{$test};

    dbg("attachment_detail: running $test\n");

    for my $attachment ( @{$permsg->{'attachments'}} ) {
        if (exists $rule->{name}) {
            my($op,$patt) = @{$rule->{name}};
            if ( ($op eq '=~' && $attachment->{name} =~ $patt) ||
                ($op eq '==' && $attachment->{name} eq $patt) ||
                ($op eq '!~' && $attachment->{name} !~ $patt) ||
                ($op eq '!=' && $attachment->{name} ne $patt) ) {
                dbg("attachment_detail: name matched: '%s' %s '%s'", $attachment->{name},$op,$patt);
            } else {
                next;
            }
        }

        if (exists $rule->{'type'}) {
            my($op,$patt) = @{$rule->{type}};
            if ( ($op eq '=~' && $attachment->{type} =~ $patt) ||
                ($op eq '==' && $attachment->{type} eq $patt) ||
                ($op eq '!~' && $attachment->{type} !~ $patt) ||
                ($op eq '!=' && $attachment->{type} ne $patt) ) {
                dbg("attachment_detail: type matched: '%s' %s '%s'", $attachment->{type},$op,$patt);
            } else {
                next;
            }
        }

        if (exists $rule->{'ext'}) {
            my($op,$patt) = @{$rule->{ext}};
            if ( ($op eq '=~' && $attachment->{ext} =~ $patt) ||
                ($op eq '==' && $attachment->{ext} eq $patt) ||
                ($op eq '!~' && $attachment->{ext} !~ $patt) ||
                ($op eq '!=' && $attachment->{ext} ne $patt) ) {
                dbg("attachment_detail: extension matched: '%s' %s '%s'", $attachment->{ext},$op,$patt);
            } else {
                next;
            }
        }

        if (exists $rule->{'disposition'}) {
            my($op,$patt) = @{$rule->{disposition}};
            if ( ($op eq '=~' && $attachment->{disposition} =~ $patt) ||
                ($op eq '==' && $attachment->{disposition} eq $patt) ||
                ($op eq '!~' && $attachment->{disposition} !~ $patt) ||
                ($op eq '!=' && $attachment->{disposition} ne $patt) ) {
                dbg("attachment_detail: disposition matched: '%s' %s '%s'", $attachment->{disposition},$op,$patt);
            } else {
                next;
            }
        }

        if (exists $rule->{'encoding'}) {
            my($op,$patt) = @{$rule->{encoding}};
            if ( ($op eq '=~' && $attachment->{encoding} =~ $patt) ||
                ($op eq '==' && $attachment->{encoding} eq $patt) ||
                ($op eq '!~' && $attachment->{encoding} !~ $patt) ||
                ($op eq '!=' && $attachment->{encoding} ne $patt) ) {
                dbg("attachment_detail: encoding matched: '%s' %s '%s'", $attachment->{encoding},$op,$patt);
            } else {
                next;
            }
        }

        if (exists $rule->{'charset'}) {
            my($op,$patt) = @{$rule->{charset}};
            if ( ($op eq '=~' && $attachment->{charset} =~ $patt) ||
                ($op eq '==' && $attachment->{charset} eq $patt) ||
                ($op eq '!~' && $attachment->{charset} !~ $patt) ||
                ($op eq '!=' && $attachment->{charset} ne $patt) ) {
                dbg("attachment_detail: charset matched: '%s' %s '%s'", $attachment->{charset},$op,$patt);
            } else {
                next;
            }
        }

        dbg("attachment_detail: criteria for $test met");
        $permsg->got_hit($test);
        return 0;
    }
    return 0;
}

sub check_attachment_count {
    my ($self, $permsg, undef, $min, $max) = @_;
    return 0 unless exists $permsg->{'attachments'};
    my $count = scalar @{$permsg->{'attachments'}};
    $count >= $min and $count <= $max;
}

1;
