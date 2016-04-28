use Proc::Builder qw/proc run/;
proc->echo('$' => 1)->set_default;

my $p = run('cat');
print STDERR $p->pid;
print $p <<EOF;
foo
bar
baz
EOF
print STDERR "Result: " . $p->slurp;
# note: $p should now be waited and closed...

print proc->combined_output->run(['foo', 'bar'])->expel('baz')->slurp;

# Opposite of slurp:
#  - spew (cf. File::Slurp->spew)
#  - expel? eject (cf. TeX)? hurl?
# "expel" is opposite of slurp - suggests that it writes and then closes
#  - or maybe 'eject' (cf. TeX) or 'hurl' or 'spew' (cf. File::Slurp->spew)
# 



# Rather than setting self as editor, can we make an editor that simply
# writes to a file and then reads from a fifo?
# Then we can do something like

my $e = proc->editor(['git', 'rebase', '-i', 'HEAD~20']);
while (<$e>) {
  print $e "foo: $_" if /bar/;
}
close $e;

#####
use Proc::Editor qw/GIT_EDITOR VISUAL EDITOR/;

run_with_editor { shift ? run_editor : s/foo/bar/g } qw/git rebase -i/;
my $out = run_editor 'abc';

Sdh::Editor::run_editor;

my $e = editor->simulate(['git', 'rebase', '-i', 'HEAD~20']);
# ...

$_ = editor->request($_);  # could use pronoun implicitly?


# This would allow maintaining variables/state inside the "editor"
