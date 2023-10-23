use lib 'lib';
use strict;
use warnings FATAL => 'all';
use Test::More;
use Mail::SpamAssassin;
use Data::Dumper;
use utf8;

my $data_dir = 't/data';
my $spamassassin = Mail::SpamAssassin->new(
    {
        dont_copy_prefs    => 1,
        local_tests_only   => 1,
        use_bayes          => 0,
        use_razor2         => 0,
        use_pyzor          => 0,
        use_dcc            => 0,
        use_auto_whitelist => 0,
        debug              => 0,
        pre_config_text        => <<'EOF'
            loadplugin Mail::SpamAssassin::Plugin::AttachmentDetail
EOF
            ,
    }
);

my @files = (
    {
        name        => 'msg1.eml',
        attachments => [
            {
                'disposition' => 'attachment',
                'encoding' => 'base64',
                'name' => 'FAX_20230301_01934829984🧾.htm',
                'charset' => undef,
                'type' => 'text/html',
                'effective_type' => 'text/html',
                'ext' => 'htm',
            }
        ]
    },
    {
        name        => 'msg2.eml',
        attachments => [
            {
                'disposition' => 'attachment',
                'encoding' => 'base64',
                'name' => '.HTM',
                'charset' => undef,
                'ext' => 'htm',
                'type' => 'application/octet-stream',
                'effective_type' => 'text/html'
            }
        ]
    },
    {
        name        => 'msg3.eml',
        attachments => [
            {
                'encoding' => 'base64',
                'type' => 'application/octet-stream',
                'effective_type' => 'text/html',
                'ext' => 'html',
                'name' => '☎®.html',
                'charset' => 'utf-8',
                'disposition' => 'attachment'
            }
        ]
    },
    {
        name        => 'msg4.eml',
        attachments => [
            {
                'name' => 'NnijYdoJHtjWGtMca65VNFfM1xgTtDAGCWJsHyJ0lCai3VOAIl.png',
                'type' => 'image/png',
                'effective_type' => 'image/png',
                'encoding' => 'base64',
                'charset' => undef,
                'ext' => 'png',
                'disposition' => 'inline'
            },
            {
                'disposition' => 'attachment',
                'encoding' => 'base64',
                'name' => 'PayApp_EFTPay219877.HTM..',
                'type' => 'application/octet-stream',
                'effective_type' => 'application/octet-stream',
                'ext' => '',
                'charset' => undef
            }
        ]
    },
    {
        name        => 'msg5.eml',
        attachments => [
            {
                'name' => 'Funds_128135.one',
                'type' => 'application/onenote',
                'effective_type' => 'application/onenote',
                'ext' => 'one',
                'encoding' => 'base64',
                'charset' => undef,
                'disposition' => 'attachment'
            },
        ]
    },
    {
        name        => 'msg6.eml',
        attachments => [
            {
                'name' => '',
                'type' => 'text/html',
                'effective_type' => 'text/html',
                'ext' => '',
                'encoding' => 'base64',
                'charset' => undef,
                'disposition' => 'attachment'
            },
        ]
    },
    {
        name        => 'msg7.eml',
        attachments => [
            {
                'charset' => undef,
                'encoding' => '',
                'ext' => '',
                'name' => 'Sign&Return',
                'disposition' => 'attachment',
                'type' => 'message/rfc822',
                'effective_type' => 'message/rfc822'
            },
            {
                'name' => 'IQEGXPVJY.JPG',
                'encoding' => 'base64',
                'ext' => 'jpg',
                'type' => 'image/jpeg',
                'effective_type' => 'image/jpeg',
                'disposition' => 'inline',
                'charset' => undef
            },
            {
                'charset' => undef,
                'ext' => 'png',
                'encoding' => 'base64',
                'name' => 'XCWHBPCFHL.png',
                'disposition' => 'inline',
                'type' => 'image/png',
                'effective_type' => 'image/png'
            }
        ]
    },

);

plan tests => scalar @files;

# test each file
foreach my $file (@files) {
    print "Testing $file->{name}\n";
    my $path = "$data_dir/".$file->{name};
    open my $fh, '<', $path or die "Can't open $path: $!";
    my $msg = $spamassassin->parse($fh);
    my $pms = $spamassassin->check($msg);
    close $fh;
    delete $_->{part} for @{$pms->{attachments}};
    # print $pms->get_report();
    # print Dumper($pms->{attachments});
    is_deeply($pms->{attachments}, $file->{attachments}, $file->{name});
}

