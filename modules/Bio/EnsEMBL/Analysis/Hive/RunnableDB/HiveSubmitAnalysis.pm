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

#!/usr/bin/env perl

package Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveSubmitAnalysis;

use strict;
use warnings;
use feature 'say';

#use Bio::EnsEMBL::Analysis::RunnableDB;
#use Bio::EnsEMBL::Pipeline::Analysis;
#use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Pipeline::Hive::HiveInputIDFactory;
#use Bio::EnsEMBL::Pipeline::DBSQL::StateInfoContainer;
use Bio::EnsEMBL::Utils::Exception qw(warning throw);
use parent ('Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveBaseRunnableDB');

sub fetch_input {
  my $self = shift;

  if($self->param('slice')) {
    my $dba = $self->hrdb_get_dba($self->param('reference_db'));
    $self->hrdb_set_con($dba);
  }

  return 1;
}

sub run {
  my $self = shift;

  if (!($self->param('slice')) && !($self->param('single')) && !($self->param('file')) &&
      !($self->param('translation_id')) && !($self->param('hap_pair')) && !($self->param('chunk'))
     ) {
    throw("Must define input as either contig, slice, file, translation_id ".
          "single, seq_level or top_level or hap_pair");
  }

  if($self->param('slice') && $self->param('chunk')) {
    throw("You have selected both the slice and the chunk file, select one or the other");
  }

  unless($self->param('chunk')) {
    my $input_id_factory = new Bio::EnsEMBL::Pipeline::Hive::HiveInputIDFactory
    (
     -db => $self->hrdb_get_con(),
     -slice => $self->param('slice'),
     -single => $self->param('single'),
     -file => $self->param('file'),
     -translation_id => $self->param('translation_id'),
     -seq_level => $self->param('seq_level'),
     -top_level => $self->param('top_level'),
     -include_non_reference => $self->param('include_non_reference'),
     -dir => $self->param('dir'),
     -regex => $self->param('regex'),
     -single_name => 'genome', # Don't know why this is set this way
     -logic_name => $self->param('logic_name'),
     -input_id_type => $self->param('input_id_type'),
     -coord_system => $self->param('coord_system_name'),
     -coord_system_version => $self->param('coord_system_version'),
     -slice_size => $self->param('slice_size'),
     -slice_overlaps => $self->param('slice_overlap'),
     -seq_region_name => $self->param('seq_region_name'),
     -hap_pair => $self->param('hap_pair'),
    );

    $input_id_factory->generate_input_ids;
    $self->output_ids($input_id_factory->input_ids);
  } else {

    if($self->param_is_defined('num_chunk') || $self->param_is_defined('seqs_per_chunk')) {
      $self->make_chunk_files();
    }
    $self->create_chunk_ids();
  }
  return 1;
}


sub make_chunk_files {
  my $self = shift;

  my $input_file;
  my $chunk_dir = $self->param('chunk_output_dir');
  my $chunk_num;

  if($self->param_is_defined('input_file_path')) {
      $input_file = $self->param('input_file_path');
  } elsif($self->param_is_defined('rechunk_dir_path') && $self->param_is_defined('rechunk')) {
    if($self->param('rechunk')) {
      $input_file = $self->param('rechunk_dir_path')."/".$self->input_id;
    }
  }

  else {
      $input_file = $self->input_id;
  }

  unless(-e $input_file) {
      throw("Your input file '".$input_file."' does not exist!!!");
  }

  unless(-e $chunk_dir) {
    `mkdir -p $chunk_dir`;
  }

  unless($self->param_is_defined('fastasplit_random_path')) {
    throw("You haven't defined a path to fastasplit_random. Please define this using the fastasplit_random_path ".
          " flag in your pipeline config");
  }

  my $fastasplit_random_path = $self->param('fastasplit_random_path');
  unless(-e $fastasplit_random_path) {
    throw("The path provided to the fastasplit_random exe does not exist. Please check the path in the config:\n".
          $fastasplit_random_path);
  }

  if($self->param_is_defined('seqs_per_chunk')) {
    my $num_seqs = `grep -c '>' $input_file`;
    $chunk_num = int($num_seqs / $self->param('seqs_per_chunk'));
  }

  say "Chunking input file to ".$chunk_num." output files";
  my $fastasplit_command = $fastasplit_random_path." ".$input_file." ".$chunk_num." ".$chunk_dir;
  my $fastasplit_exit_code = system($fastasplit_command);
  unless($fastasplit_exit_code == 0){
    throw($fastasplit_random_path." returned an error code:\n".$fastasplit_exit_code);
  }

}


sub create_chunk_ids {
  my $self = shift;

  my $input_file;
  my $chunk_dir = $self->param('chunk_output_dir');


  if($self->param_is_defined('input_file_path')) {
      $input_file = $self->param('input_file_path');
    } else {
      $input_file = $self->input_id;
  }

  # Get the name without the extension as fastasplit_random cuts off the extension
  $input_file =~ /[^\/]+$/;
  $input_file = $&;
  $input_file =~ s/\.[^\.]+$//;

  my @chunk_array = glob $chunk_dir."/".$input_file."_chunk_*";

  unless(scalar(@chunk_array)) {
    throw("Found no files in chunk dir using glob. Chunk dir:\n".
          $chunk_dir."/"."\nChunk generic name:\n".$input_file."_chunk_*");
  }

  for(my $i=0; $i < scalar(@chunk_array); $i++) {
    $chunk_array[$i] =~ /[^\/]+$/;
    $chunk_array[$i] = $&;
  }
  $self->output_ids(\@chunk_array);
}


sub write_output {
  my $self = shift;

  my $output_ids = $self->output_ids();

  unless(scalar(@{$output_ids})) {
    warning("No input ids generated for this analysis!");
  }

  foreach my $output_id (@{$output_ids}) {

    if($self->param_is_defined('skip_mito') && ($self->param('skip_mito') == 1 || $self->param('skip_mito') eq 'yes') &&
       $self->param_is_defined('slice') && ($self->param('slice') == 1 || $self->param('slice') eq 'yes') &&
       $output_id =~ /^.+\:.+\:MT\:/) {
       next;
    }

    my $output_hash = {};
    $output_hash->{'iid'} = $output_id;
    $self->dataflow_output_id($output_hash,1);
  }

  return 1;
}


sub input_id_factory {
 my ($self,$value) = @_;

  if (defined $value) {
    unless($value->isa('Bio::EnsEMBL::Pipeline::Hive::HiveInputIDFactory')) {
      throw("To set an input id factory object it must be of type Bio::EnsEMBL::Pipeline::Hive::HiveInputIDFactory, not a ".$value);
    }
    $self->param('_input_id_factory',$value);
  }

  return self->param('_input_id_factory');
}


sub output_ids {
 my ($self,$value) = @_;

  if (defined $value) {
    $self->param('_output_ids',$value);
  }

  return $self->param('_output_ids');
}

1;
