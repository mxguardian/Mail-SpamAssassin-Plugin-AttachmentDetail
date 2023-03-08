use lib 'lib';
use strict;
use warnings FATAL => 'all';
use Test::More;
use Mail::SpamAssassin;
use Data::Dumper;

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
                'type' => 'text/html'
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
                'type' => 'application/octet-stream'
            }
        ]
    },
    {
        name        => 'msg3.eml',
        attachments => [
            {
                'encoding' => 'base64',
                'type' => 'application/octet-stream',
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
                'encoding' => 'base64',
                'charset' => undef,
                'disposition' => 'inline'
            },
            {
                'disposition' => 'attachment',
                'encoding' => 'base64',
                'name' => 'PayApp_EFTPay219877.HTM..',
                'type' => 'application/octet-stream',
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
                'encoding' => 'base64',
                'charset' => undef,
                'disposition' => 'attachment'
            },
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
    # print $pms->get_report();
    # print Dumper($pms->{attachments});
    is_deeply($pms->{attachments}, $file->{attachments}, $file->{name});
}

