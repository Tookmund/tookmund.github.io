_site: vendor/bundle
	bundler exec jekyll build

serve: vendor/bundle
	bundler exec jekyll serve --drafts

vendor/bundle:
	bundler install --path vendor/bundle

clean-site:
	rm -rvf _site

clean-vendor:
	rm -rvf vendor

.PHONY: serve clean-site clean-vendor
