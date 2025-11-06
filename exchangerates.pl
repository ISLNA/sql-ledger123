#!/usr/bin/env perl

use Mojo::UserAgent;
use Mojo::JSON qw(decode_json);
use DBIx::Simple;
use DBD::Pg;
use POSIX qw(strftime);
use Data::Dumper;

for my $dbname (qw(yourdatabase-1 yourdatabase-2 etc)) {
    &update_fxrate($dbname);
}

sub update_fxrate {
    my $dbname            = shift;
    my $db                = DBIx::Simple->connect( "dbi:Pg:dbname=$dbname", 'sql-ledger' );
    my $base_currency     = $db->query('SELECT curr FROM curr WHERE rn=1')->list;
    my @target_currencies = $db->query('SELECT curr FROM curr WHERE rn > 1')->flat;
    my $url               = "https://api.frankfurter.app/latest?base=$base_currency&symbols=" . join( ',', @target_currencies );
    my $transdate         = strftime "%Y/%m/%d", localtime;
    my $ua                = Mojo::UserAgent->new;
    my $tx                = $ua->get($url)->result;

    if ( my $res = $tx->is_success ) {
        my $json = decode_json( $tx->body );
        foreach my $target_currency (@target_currencies) {
            my ($existing_rate) = $db->query( 'SELECT buy FROM exchangerate WHERE curr = ? AND transdate = ?', $target_currency, $transdate )->list;
            if ( !$existing_rate ) {
               my $rate = $json->{'rates'}->{$target_currency};
               if ($rate){
                        my $fxrate = 1/$rate;
                        my $roundedrate = sprintf("%.3f", $fxrate);
                        $db->query( 'INSERT INTO exchangerate (curr, transdate, buy, sell) VALUES (?, ?, ?, ?)', $target_currency, $transdate, $roundedrate, $roundedrate );
                }
            }
        }
    } else {
        my $err = $tx->error;
        print "Error: $err->{code} response: $err->{message}\n" if $err;
    }

}

# EOF
