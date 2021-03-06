#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveDownloadUniProtFiles;

use strict;
use warnings;
use feature 'say';


use Bio::EnsEMBL::Utils::Exception qw(warning throw);
use parent ('Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveBaseRunnableDB');

sub fetch_input {
  my $self = shift;
  return 1;
}

sub run {
  my $self = shift;

  my $query_url = $self->build_query();
  say "Downloading:\n".$query_url."\n";

  my $query_exit_code;
  $query_exit_code = system($query_url);
  unless($query_exit_code == 0) {
    throw("The wget query ended in an non-zero exit code:\n".$query_exit_code);
  }

  if($query_url =~ /\.gz$/) {
    my $file_path = $self->param('dest_dir')."/".$self->param('file_name');
    my $gunzip_command = "gunzip ".$file_path;
    my $gunzip_exit_code;
    $gunzip_exit_code = system($gunzip_command);
    unless($gunzip_exit_code == 0) {
      throw("gunzip on file ended in an non-zero exit code:\n".$gunzip_exit_code);
    }
  }

  say "Finished downloading UniProt files";
  return 1;
}

sub write_output {
  my $self = shift;

  my $file_path = $self->param('dest_dir')."/".$self->param('file_name');

  my $output_hash = {};
  $output_hash->{'iid'} = $file_path;
  $self->dataflow_output_id($output_hash,1);

  return 1;
}

sub build_query {
  my ($self) = @_;
  my $tax_group = 0;
  my $taxon_id;
  my $taxonomy;
  my $dest_dir;
  my $file_name;
  my $pe_string = "(";
  my $taxonomy_string = "";
  my $compress = "yes";
  my $fragment_string = "+AND+fragment:no";
  my $mito = "+NOT+organelle%3Amitochondrion";
  my $format = "fasta";

  my $full_query = "wget -q -O - \"http://www.uniprot.org/uniprot/?query=";
  my %pe_code = (
                  '1' => 'evidence+at+protein+level',
                  '2' => 'evidence+at+transcript+level',
                  '3' => 'inferred+from+homology',
                  '4' => 'predicted',
                  '5' => 'uncertain',
                );

  # Must have file_name, pe_level, dest_dir and either taxon_id or taxonomy
  unless($self->param_is_defined('file_name') && $self->param_is_defined('dest_dir') &&
        ($self->param_is_defined('taxon_id') || $self->param_is_defined('taxonomy')) &&
         $self->param_is_defined('pe_level')) {
    throw("Must define the following keys:\nfile_name\ntaxon_id or taxonomy\ndest_dir\npe_level");
  }

  $file_name = $self->param('file_name');
  $dest_dir = $self->param('dest_dir');

  my @pe_array = split(',',$self->param('pe_level'));
  unless(scalar(@pe_array)) {
    die "Not PE levels found in value of pe_levels key. Format should be: '1,2'";
  }
  foreach my $pe_level (@pe_array) {
    unless($pe_level =~ /\d+/) {
     die "Could not parse a PE level from the following: ".$pe_level;
    }

    my $parsed_pe_level = $&;
    unless($parsed_pe_level >= 1 && $parsed_pe_level <= 5) {
     die "Parsed PE level is outside the normal range of 1-5: ".$parsed_pe_level;
   }
   $pe_string .= 'existence%3A%22'.$pe_code{$pe_level}.'%22+OR+';
  }

  $pe_string =~ s/\+OR\+$/\)/;


  if($self->param('taxon_id')) {
    $taxon_id = $self->param('taxon_id');
    $taxonomy_string = '+AND+taxonomy%3A+'.$taxon_id;
  } elsif($self->param('taxonomy')) {
    $taxonomy = $self->param('taxonomy');
    $taxonomy_string = '+AND+taxonomy%3A'.$taxonomy;
  }

  if($self->param_is_defined('compress') && ($self->param('compress') eq '0' || $self->param('compress') eq 'no')) {
    $compress = "no";
  }
  if($self->param_is_defined('fragment') && ($self->param('fragment') eq '1' || $self->param('fragment') eq 'yes')) {
    $fragment_string = "";
  }
  if($self->param_is_defined('format') && ($self->param('format') ne 'fasta' && $self->param('format') ne '')) {
    $format = $self->param('format');
  }
  if($self->param_is_defined('mito') && ($self->param('mito') eq '1' || $self->param('mito') eq 'yes')) {
    $mito = "";
  }

  $full_query .= $pe_string.$taxonomy_string.$fragment_string.$mito."&compress=".$compress."&format=".$format.
                 "\" > ".$dest_dir."/".$file_name;
  if($compress eq 'yes') {
    $full_query .= ".gz";
  }

  unless(-e $dest_dir) {
    `mkdir -p $dest_dir`;
  }

  return($full_query);
}

1;
