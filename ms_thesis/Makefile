PDFLATEX_FLAGS = -halt-on-error -output-format pdf -output-directory build/ -shell-escape

.PHONY: clean

thesis.pdf: thesis.tex abstract.tex references.bib chap1.tex chap2.tex chap3.tex chap4.tex
	mkdir -p build/
	pdflatex $(PDFLATEX_FLAGS) thesis.tex
	biber --output-directory build/ thesis
	pdflatex $(PDFLATEX_FLAGS) thesis.tex
	pdflatex $(PDFLATEX_FLAGS) thesis.tex
	cp build/thesis.pdf ./thesis.pdf

clean:
	rm -rf build/
	rm -f thesis.pdf
