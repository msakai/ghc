test('T16586', normal, compile_and_run, ['-O2'])
# Event-manager not supported on Windows
test('T16916', when(opsys('mingw32'), skip), compile_and_run, ['-O2 -threaded -with-rtsopts="-I0" -rtsopts'])
test('T17310', normal, compile, [''])
