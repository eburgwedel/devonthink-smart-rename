#!/usr/bin/perl -l -w
#region use

use v5.14;

use utf8;
use strict;
use autodie;
use warnings;
use warnings qw( FATAL utf8 );
use open qw( :encoding(UTF-8) :std );
use charnames qw( :full :short );
use feature 'unicode_strings';

use Data::Dumper;
use Date::Manip;

use File::Basename qw( basename );
use Carp qw( carp croak confess cluck );
use Encode;
use Encode::Locale;
use Unicode::Normalize qw( NFD NFC );

END { close STDOUT }

use constant false => 0;
use constant true  => 1;

#endregion use

# Set to 0 for normal operation
# Set to 1 to use test data and minimal debug output
# Set to 2 to add basic debug output
# Set to 3 to add extreme debug output
use constant debug => 0;

# Conversion doesn't work this way
# @ARGV = map { decode( locale => $_ ) } @ARGV;

# Convert ARGV into unicode from UTF-8
# For all the unicode pains, see https://stackoverflow.com/questions/6162484/why-does-modern-perl-avoid-utf-8-by-default/6163129%236163129
if ( grep /\P{ASCII}/ => @ARGV ) {
    @ARGV = map { decode( "UTF-8", $_ ) } @ARGV;
}
print @ARGV if debug > 2;

# Get args from the command line
my ( $fileName, $documentDate, $appendString ) = @ARGV;
print Dumper @ARGV               if debug > 2;
print "ARGV Filename: $fileName" if debug > 2;

#region setup
my @strings;
$strings[0] = $fileName;

# Check if all necessary arguments are present, othwerwise exit
# or continue with test data (if debug > 0)
my $has_args = checkARGS();
exit          if !$has_args && !debug;
setTestData() if !$has_args;

# Get today's date to prepend if no other date is available
# And no, it doesn't work in only one line
my $today = `date +"%Y-%m-%d"`;
chomp($today);

my $date_ISO        = qr/(\d\d\d\d_\d\d_\d\d) | (\d\d\d\d-\d\d-\d\d)/x;
my $date_ISO_Strict = qr/(\d\d\d\d-\d\d-\d\d)/x;
my $date_US         = qr/(\d\d\/\d\d\/\d\d\d\d)/x;
my $date_DE         = qr/(\d\d\.\d\d\.(?:\d\d){1,2})(?:[^\d]|$)/x;
my $dateTime_ISO    = qr/(\d\d\d\d_\d\d_\d\d _ \d\d_\d\d_\d\d)/x;
my $notLeading      = qr/(.*)(?<!^)/x;

my @dates;

#endregion setup

# https://www.perl.com/pub/2012/05/perlunicookbook-unicode-normalization.html
@strings      = map { NFC($_) } @strings;
$appendString = NFC($appendString);

# Initalize and clean AppendString
$appendString = $appendString ? trim( convertUnicode($appendString) ) : '';

# Check AppendString for valid date, override any leading date if yes
my $dateCandidate = detectDate($appendString);
my $dateOveride   = $dateCandidate ? true : false;
$documentDate = $dateCandidate || $documentDate;

print "00 AppendString: $appendString"    if debug > 2;
print "01 Date Candidate: $dateCandidate" if debug > 2;
print "02 Date Override: $dateOveride"    if debug > 2;

foreach my $string (@strings) {

    print "03: $string" if debug;

    # Get rid of leading and trailing garbage
    # Todo: check if necessary
    $string = trim( convertUnicode($string) );
    print "04: $string" if debug > 1;

    # exit;

    # Append AppendString only if not a date
    $string .= ' - ' . $appendString
      unless $dateCandidate or !$appendString;
    print "05: $string" if debug > 1;

    # Get all raw dates from string
    @dates = $string =~ / $dateTime_ISO | $date_ISO | $date_US | $date_DE /gx;

    # Filter list to remove all undefined
    @dates = grep( defined, @dates );

    # Preserve all dates for later replacement mapping
    my @originalDates = @dates;
    print Dumper @originalDates if debug > 2;

    # Run regex (dateTime_ISO -> date_ISO) against all elements of the array
    @dates = map {
        ( my $s = $_ ) =~
          s/(\d\d\d\d)_(\d\d)_(\d\d) _ \d\d_\d\d_\d\d/$1-$2-$3/gx;
        $s
    } @dates;

    # Run regex ('_' -> '-') against all elements of the array
    @dates = map { ( my $s = $_ ) =~ s/_/-/g; $s } @dates;

    # Replace all German dates DD.MM.YY(YY) with YYYY-MM-DD
    @dates = map {
        ( my $s = $_ ) =~ s/ (\d\d) \. (\d\d) \. ((?:\d\d){1,2}) /$3-$2-$1/gx;
        $s
    } @dates;

    # Parse the dates into YYYY-MM-DD or leave it untouched
    @dates = map { UnixDate( ParseDate($_), '%Y-%m-%d' ) || $_ } @dates;
    print Dumper @dates if debug > 2;

    # Eleminating duplicates, using a hash
    my %seen;
    @dates = map { !$seen{$_}++ ? $_ : '' } @dates;
    print Dumper @dates if debug > 2;

    # Concat all dates into one search patten and capture the parts inbetween
    # Use quotemeta to escape all non-literal characters to function in regex
    my $find = join( '(.*)', map { quotemeta($_) } @originalDates ) . '(.*)';

    # Concat all replacements with each a subsequent backreference
    # But make sure that if @dates is empty we replace string with itself ($1)
    my $i;
    my $replace =
      $#dates == -1 ? '${1}' : join( '', map { $i++; "$_\${$i}" } @dates );

    # Put it in quotes so that s/x/y/ee can evaluate
    $replace = '"' . $replace . '"';

    print "Find: $find"       if debug > 2;
    print "Replace: $replace" if debug > 2;

# Double evaluate the replacement string
# See: https://stackoverflow.com/questions/392643/how-to-use-a-variable-in-the-replacement-side-of-the-perl-substitution-operator
    $string =~ s/$find/$replace/ee;
    print "06: $string" if debug > 1;

    # If date override, replace first date in string with document date
    $string =~ s/ $date_ISO_Strict /$documentDate/x if $dateOveride;

    # Make first date found in string leading date
    $string =~ s/ (.*?) $date_ISO_Strict/$2 $1 /x;
    print "07: $string" if debug > 1;

    # If no date at all yet, add prepending date,
    # either document date or today's date
    $string = ( $documentDate || $today ) . $string
      if !grep { $_ =~ /\d\d\d\d-\d\d-\d\d/ } $string;
    print "08: $string" if debug > 1;

    # Clean
    $string = clean($string);

    print debug ? "09: $string" : $string;
    print "----------\n" if debug;
}

# Check if all commandline arguments are present
sub checkARGS {

    my $num_args = $#ARGV + 1;
    print "Args: $num_args\n------" if debug;

    # No error if no command line args in debug mode
    return false if ( $num_args == 0 && debug );

    if ( $num_args < 1 ) {
        print
          "\nUsage: namewrangler.pl Filename [Document Date] [Append String]\n";
        print "Filename: String\nDocument Date: String (YYYY-MM-DD)";
        print "Append String: String\n";
        print "Note: If Append String is present,";
        print "Document Date needs to be present, too.\n";
        return false;
    }
    return true;
}

# Remove unwanted characters
sub clean {
    my ($input) = @_;

    # Remove line breaks
    $input =~ s/[\r\n]/ /gm;

    # Replace "_" in numbers with "-"
    $input =~ s/(\d)_(\d)/$1-$2/gm;

    # Replace "," in numbers with "."
    $input =~ s/(\d),(\d)/$1.$2/gm;

    # Remove all unwanted characters
    $input =~ s/[^-A-Za-z0-9À-ȕ. +_@()'€$%&"—-]//gm;
    $input =~ s/([. +_@()'"—-]){1}(\1)+/$1/gm;

    # Replace "_" with " "
    $input =~ s/[_]/ /gm;

    # Remove anything but " " after leading date
    # $input =~ s/ ^$date_ISO_Strict [^A-Za-z0-9'"]* /$1 /gmx;
    $input =~ s/ ^$date_ISO_Strict [^A-Za-zÀ-ȕ0-9'"]* /$1 /gmx;

    # Replace "word -word" and "word- word" with "word - word"
    $input =~ s/ -(\w)/ - $1/gm;
    $input =~ s/(\w)- /$1 - /gm;
    $input =~ s/ *([-–—]) [-–—] */ $1 /gm;

    # Replace multiple blanks with a single one
    $input =~ s/ +/ /gm;

    # Custom cleaners for my personal taste
    $input =~ s/invoice/Invoice/gm;
    $input =~ s/Invoice[^ ](?!$)/Invoice /gm;

    # Remove leading and trailing blanks and characters
    trim($input);

    # Titlecase (experimental)
    $input =~ s/([^.]\b[[:lower:]])(\w)/\U$1\L$2/gx;

    return $input;
}

# Remove unwanted leading or trailing character (not just blanks)
sub trim {
    my ($input) = @_;

    # Leading
    $input =~ s/^[^(A-Za-zÀ-ȕ0-9"'@\$%&§€]*//gmx;
    print "Trim 1: $input" if debug > 2;

    # Trailing
    $input =~ s/[^A-Za-zÀ-ȕ0-9?"')@\$%&§€]*$//gmx;
    print "Trim 2: $input" if debug > 2;

    return $input;
}

# Convert quotes and other unicode characters to ascii
sub convertUnicode {
    my ($input) = @_;

    # Remove or replace specific characters
    $input =~ s/:/ \N{EM DASH}/gm;

    # Remove or replace specific characters
    # $input =~ s///gm;

    # Single Quotes
    $input =~ s/[\x{2018}\x{201A}\x{201B}\x{FF07}\x{2019}\x{60}]/\x27/g;

    # Double Quotes
    $input =~ s/[\x{FF02}\x{201C}\x{201D}\x{201E}\x{275D}\x{275E}]/"/g;

    return $input;
}

# Check if a string is a US or DE date. Return as ISO YYYY-MM-DD
sub detectDate {
    my ($dateCandidate) = @_;

    print "A Date Candidate: $dateCandidate" if debug > 2;

    # print $dateCandidate;

    # my $dateCandidate = '01. Juni 2020';
    # my $dateCandidate = '12.04.2020';
    # my $dateCandidate = '2020-04-30';
    # my $dateCandidate = '04/10/2020';
    # my $dateCandidate = '22. Mai 2020';

    my ( $dateDE, $dateISO, $dateUS, $resultISO );

    # Check if only numbers; if only numbers, does it match YYYYMMDD?
    my $justNumbers = $dateCandidate =~ /^\d+$/;
    my $looksLikeDateISO =
      $dateCandidate =~ /\b(\d{4})(0[1-9]|1[0-2])(0[1-9]|[12]\d|30|31)\b/;
    return '' if ( $justNumbers && !$looksLikeDateISO );

    # Is it a straight forward German date (30.01.2020)?
    if ( $dateCandidate =~ /^$date_DE$/x ) {
        Date_Init( "Language=German", "DateFormat=non-US" );

        $dateDE = ParseDate($dateCandidate);
        print "B DE Date: $dateDE" if debug > 2;
    }

    # Is it a straight forward US date (01/30/2020)?
    elsif ( $dateCandidate =~ /^$date_US$/x ) {
        Date_Init( "Language=English", "DateFormat=US" );

        $dateUS = ParseDate($dateCandidate);
        print "C US Date: $dateUS" if debug > 2;
    }
    else {
        # Check all possibilities

        # Remove . from date string (Data::Manip can't deal with it)
        $dateCandidate =~ s/\./ /gmx;

        Date_Init( "Language=English", "DateFormat=US" );
        $dateUS = ParseDate($dateCandidate);

        print "D US Date: $dateUS" if debug > 2;

        Date_Init( "Language=German", "DateFormat=non-US" );
        $dateDE = ParseDate($dateCandidate);

        print "E DE Date: $dateDE" if debug > 2;

        Date_Init( "Language=English", "DateFormat=US" );
    }

    if ( !$dateUS && !$dateDE ) {

        print "Bad Date" if debug > 1;
        $resultISO = '';
    }
    else {
        $resultISO = $dateDE ? $dateDE : $dateUS;
        $resultISO = UnixDate( $resultISO, '%Y-%m-%d' );
    }

    return $resultISO;
}

# Initalize testData for development, overrides ARGV
#region setTestData
sub setTestData {

    $documentDate = $documentDate || '2020-06-03';
    $appendString = $appendString || ' company
OFFER 1234-56-78 Content
STUFF';

    # $appendString = '20201020';
    # $appendString = "13. Mai 2020";
    $appendString =
      "„Das Produkt war überaus zwingend“ - Bestellbestätigung";

    @strings = (
        'Möbel Fotos - IMG 3780',
        '2020_08_10 Some filename with Ümlaut',
        '10/20/2020 Words after a US-Date',
        ' 30.04.2020 Words after a German date',
        'Abc 30.04.2020 German Date and Some More Text',
        '-Some Leading Word #30.04.2021 Some text at the end-',
        '_+Here\'s nothing - no date',
        '#Some garbage Leading #30.04.2021 Some garbage at the end;',
        '#2019-12-31 Leading Word 30.04.2021 -#Some other text at the end',
        'Leading Word 30.04.21 -#Some other text at the end',
        '9999-12-11-Hallo World_',
        '2020-05-10 Company — Document Order_Test_052019',
        '2016_09_04_20_53_43',
        '2017_10_12_16_13_36 Lorem Ipsum Scan Name',
        '2019-11-08 - 2019_11_08_16_23_16 And even 2019-11-08 more dates',
'2016-10-24 12_23_12345678_Bestätigung der Annahme GeSt (GeSt 1 A) 2015_ServiceOnline',
'2020-05-26 Invoice - Company HG3H293D - 1234567890 -9.99 EUR.pdf',
        'ScreenShot 2020-05-26 at 11.06.20@2x',
        '„Das Urteil: war — zwingend“',
"2020-05-13 'Das Urteil war zwingend' - Frankfurter — Allgemeine Zeitung - TEST",
        'Der Betrag ist 31,99 EUR'
    );

}

#endregion setTestData
