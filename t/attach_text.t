use lib 'lib';
use strict;
use warnings FATAL => 'all';
use Test::More;
use Mail::SpamAssassin;

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
        pre_config_text    => <<'EOF'
            loadplugin Mail::SpamAssassin::Plugin::AttachmentDetail
            attach_text  ATTACH_BITCOIN    /\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b/
            attach_text  ATTACH_PAYMENT    /amount due/i
            attach_text  ATTACH_NOMATCH    /this should not match anything in attachment/
EOF
            ,
    }
);

my @tests = (
    {
        name => 'msg10.eml',
        hits => {
            'ATTACH_BITCOIN' => 1,
            'ATTACH_PAYMENT' => 1,
        },
        description => 'text attachment with bitcoin address and payment text',
    },
    {
        name => 'msg8.eml',
        hits => {},
        description => 'text attachment with no matching content',
    },
);

plan tests => scalar @tests;

foreach my $test (@tests) {
    my $path = "$data_dir/$test->{name}";
    open my $fh, '<', $path or die "Can't open $path: $!";
    my $msg = $spamassassin->parse($fh);
    my $pms = $spamassassin->check($msg);
    close $fh;

    my $hits = $pms->get_names_of_tests_hit_with_scores_hash();
    foreach my $name (keys %$hits) {
        delete $hits->{$name} unless $name =~ /^ATTACH_/;
    }
    is_deeply($hits, $test->{hits}, "$test->{name} - $test->{description}");
}
