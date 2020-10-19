INSTALL_PREFIX?=/usr/local/bin
.PHONY: buildfs

buildfs:
	dune build -p buildfs
	dune install

clean:
	dune clean

install:
	install -D -o root make-instrumentation/fsmake-make "${INSTALL_PREFIX}/fsmake-make"
	install -D -o root make-instrumentation/fsmake-shell "${INSTALL_PREFIX}/fsmake-shell"
	install -D -o root gradle-instrumentation/fsgradle-gradle "${INSTALL_PREFIX}/fsgradle-gradle"

uninstall:
	rm -f "${INSTALL_PREFIX}/fsmake-make"
	rm -f "${INSTALL_PREFIX}/fsmake-shell"
	rm -f "${INSTALL_PREFIX}/fsgradle-gradle"
