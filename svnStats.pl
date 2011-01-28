#!/usr/bin/perl

use Getopt::Std;

getopts("c:d:l:ht:r:", \%opts);

if ($opts{h}) {
	print STDERR "Usage: $0 [options]\n\n";
	print STDERR "Options:\n";
	print STDERR "\t-d [dir]\t\tDirectory to examine, otherwise the current working directory.\n";
	print STDERR "\t-l [limit]\t\tLimit the number of log entries to pull. Default: unlimited.\n";
	print STDERR "\t-r [revrange]\t\tLimit the number of log to the given revision range. Format is SVN standard.\n";
	print STDERR "\t-c [percnt]\t\tOnly show the top 'percnt' percentage of committers, by number of commits.\n";
	print STDERR "\t-t [csvfile]\t\tCreate CSV output of committer information in 'csvfile'.\n";
	print STDERR "\t-h\t\t\tThis help.\n";
	exit(0);
}

my $dir = $opts{d} || `pwd`;
chomp($dir);

print "Examining directory '$dir'...\n";

$cmd = "svn log -v " . ($opts{l} ? "--limit $opts{l}" : "") . ($opts{r} ? "-r$opts{r}" : "") . " $dir";
print "Running command '$cmd'...\n";
$output = `$cmd`;

print "Outputing tabular data into '$opts{t}'...\n", if ($opts{t});

@logs = split(/\-{70,73}/, $output);
$stats = {};

$linesTotal = 0;
$modTotal = 0;
$addTotal = 0;
$delTotal = 0;
$comTotal = 0;

foreach my $l (@logs)
{
	$inChangedLinesSection = 0;
	$inLogSection = 0;
	$lName = undef;
	$lRev = undef;
	
	foreach (split(/\n/, $l)) {
		#print "<< [[ $inChangedLinesSection $inLogSection ]] $_ >> ($lName $lRev)\n";
		if (/r(\d+)\s+\|\s+(\w+)\s+\|\s+([\d\-]+\s+[\d:]+\s+\-\d+).*(\d+)\s+lines?/ig) {
			$lName = $2;
			$stats->{$2}->{allRevisions}->{($lRev = $1)} = {dateTime => $3, lines =>$4};
			$stats->{$2}->{linesTotal} += int($4);
			$linesTotal += int($4);
			$stats->{$2}->{commitsTotal}++, $comTotal++;
		}
		
		$inChangedLinesSection = 1, if (/Changed paths:/);
		
		if ($inChangedLinesSection) {
			$lh = $stats->{$lName};
			if (/\s+(\w)\s+(.*)/ig) {
				$modTotal++, $lh->{modifiedTotal}++, $lh->{allRevisions}->{$lRev}->{modifiedFiles}++, if ($1 eq 'M');
				$addTotal++, $lh->{addedTotal}++, $lh->{allRevisions}->{$lRev}->{addedFiles}++, if ($1 eq 'A');
				$delTotal++, $lh->{deletedTotal}++, $lh->{allRevisions}->{$lRev}->{deletedFiles}++, if ($1 eq 'D');
			}
		}
		
		$inLogSection = 1, $inChangedLinesSection = 0, if ($inChangedLinesSection && /^\s*$/);
		
		if ($inLogSection) {
		}
	}
}

#use Data::Dumper;
#print Dumper($stats);

$commitMax = [0, undef];
$lpcMax = [0, undef];
$linesMax = [0, undef];
$modMax = [0, undef];
$addMax = [0, undef];
$delMax = [0, undef];

foreach my $c (sort(keys(%{$stats}))) {
	my $u = $stats->{$c};
	my $lpc = $u->{linesTotal} / $u->{commitsTotal};
	
	$linesMax = [$u->{linesTotal}, $c], if ($u->{linesTotal} > $linesMax->[0]);
	$commitMax = [$u->{commitsTotal}, $c], if ($u->{commitsTotal} > $commitMax->[0]);
	$lpcMax = [sprintf("%0.2f", $lpc), $c], if ($lpc > $lpcMax->[0]);
	$modMax = [$u->{modifiedTotal}, $c], if ($u->{modifiedTotal} > $modMax->[0]);
	$addMax = [$u->{addedTotal}, $c], if ($u->{addedTotal} > $addMax->[0]);
	$delMax = [$u->{deletedTotal}, $c], if ($u->{deletedTotal} > $delMax->[0]);
}

print "\n-- Overall totals:\n";
print "\tCommitters:\t" . scalar(keys(%{$stats})) . "\n";
print "\tCommits:\t$comTotal\n";
print "\tChanged lines:\t$linesTotal\n", if ($linesTotal);
print "\tLines/commit:\t" . sprintf("%0.2f", ($linesTotal / $comTotal)) . "\n";
print "\tModified files:\t$modTotal\n", if ($modTotal);
print "\tAdded files:\t$addTotal\n", if ($addTotal);
print "\tDeleted files:\t$delTotal\n", if ($delTotal);
print "\n-- Committers" . ($opts{c} ? " (top $opts{c}% by commits)" : "") . ":\n";

if ($opts{t}) {
	open ($csvf, "+>$opts{t}") or die "$!: $opts{t}\n\n";
	print $csvf "Committer,Commits,Lines,Lines/commit,FilesAdded,FilesDeleted,FilesModified\n";
}

foreach my $c (sort(keys(%{$stats}))) {
	my $u = $stats->{$c};
	my $lpc = $u->{linesTotal} / $u->{commitsTotal};
	
	if (!$opts{c} || ($opts{c} && $u->{commitsTotal} >= ($commitMax->[0] * ((100 - $opts{c}) / 100)))) {
		print "--- $c\n";
		print "\tCommits:\t$u->{commitsTotal}\n";
		print "\tLines:\t\t$u->{linesTotal}\n";
		print "\tLines/commit:\t" . sprintf("%0.2f", $lpc) . "\n";
		print "\tFiles added:\t$u->{addedTotal}\n", if ($u->{addedTotal});
		print "\tFiles deleted:\t$u->{deletedTotal}\n", if ($u->{deletedTotal});
		print "\tFiles modified:\t$u->{modifiedTotal}\n", if ($u->{modifiedTotal});
		
		print $csvf "$c,$u->{commitsTotal},$u->{linesTotal},$lpc,$u->{addedTotal},$u->{deletedTotal},$u->{modifiedTotal}\n", if ($opts{t});
	}
}

close($csvf), if ($opts{$t});

print "\n-- Maximums:\n";
print "--- Lines:\t\t'$linesMax->[1]' with $linesMax->[0]\n", if ($linesMax->[0]);
print "--- Commits:\t\t'$commitMax->[1]' with $commitMax->[0]\n", if ($commitMax->[0]);
print "--- Lines/commit:\t'$lpcMax->[1]' with $lpcMax->[0]\n", if ($lpcMax->[0]);
print "--- Files modified:\t'$modMax->[1]' with $modMax->[0]\n", if ($modMax->[0]);
print "--- Files added:\t'$addMax->[1]' with $addMax->[0]\n", if ($addMax->[0]);
print "--- Files deleted:\t'$delMax->[1]' with $delMax->[0]\n", if ($delMax->[0]);