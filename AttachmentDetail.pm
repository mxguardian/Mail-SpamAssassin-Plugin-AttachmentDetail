# <@LICENSE>
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to you under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# </@LICENSE>

# Author:  Kent Oyer <kent@mxguardian.net>

=head1 NAME

AttachmentDetail - SpamAssassin plugin to check attachment details

=head1 DESCRIPTION

This plugin creates a new rule test type, called "attachment".  These
rules apply to all attachments found in the message. Any MIME part
that has a filename is considered an "attachment" regardless of the content
disposition.

This provides a simpler way to write rules based on filenames and MIME types without having to
parse MIME headers yourself.

=head1 SYNOPSIS

  loadplugin    Mail::SpamAssassin::Plugin::AttachmentDetail

  attachment    INVALID_HTML_TYPE       name =~ /\.s?html?/i type != text/html
  attachment    GEEKSQUAD_IMAGE_SPAM    name =~ /^geek/i type =~ /^image\//
  attachment    TRAILING_DOT            name =~ /\.$/
  attachment    DOUBLE_EXTENSION        name =~ /\.[^.\/\s]{2,4}\.[^.\/\s]{2,4}$/i
  ...

=head1 RULE DEFINITIONS AND PRIVILEGED SETTINGS

The format for defining a rule is as follows:

  attachment SYMBOLIC_TEST_NAME key1 =~ /value1/i  key2 == value2 ...

Supported keys are:

C<name> is the suggested filename as specified in the Content-Type header

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

=head1 ACKNOWLEDGEMENTS

This plugin was modeled after the URIDetail plugin

=cut

package Mail::SpamAssassin::Plugin::AttachmentDetail;
use strict;
use warnings FATAL => 'all';
use v5.12;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger;
use Mail::SpamAssassin::Util qw(compile_regexp);

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

                if ($target !~ /^(?:name|type|disposition|encoding|charset)$/) {
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
    my $pms = $opts->{permsgstatus};
    my $msg = $opts->{msg};

    # gather info on attachments
    foreach my $p ($pms->{msg}->find_parts(qr/./, 1)) {
        my ($type, $boundary, $charset, $name) =
            Mail::SpamAssassin::Util::parse_content_type($p->get_header('content-type'));
        next unless defined($name);

        my $cte = $p->get_header('content-transfer-encoding') || '';
        chomp $cte;

        my $cd = $p->get_header('content-disposition') || '';
        chomp $cd;
        $cd = $1 if $cd =~ /^(\S+)(?:;|$)/;

        push @{$pms->{'attachments'}}, {
            'type'        => $type,
            'name'        => $name,
            'encoding'    => $cte,
            'charset'     => $charset,
            'disposition' => $cd,
        };

    }

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

1;