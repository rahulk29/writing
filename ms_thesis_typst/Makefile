.PHONY: default clean

default: thesis.pdf

thesis.pdf: thesis.typ template.typ refs.bib $(wildcard figures/**/*)
	typst compile thesis.typ

clean:
	rm -f thesis.pdf
