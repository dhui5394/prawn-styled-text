lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'prawn-styled-text/version'

Gem::Specification.new do |spec|
  spec.name          = 'prawn-styled-text'
  spec.version       = PrawnStyledText::VERSION
  spec.summary       = 'Prawn PDF styled text'
  spec.description   = 'A Prawn PDF component which adds basic HTML support'
  spec.license       = 'MIT'
  spec.authors       = ['Mattia Roccoberton']
  spec.email         = 'mat@blocknot.es'
  spec.homepage      = 'https://github.com/blocknotes/prawn-styled-text'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'prawn', '~> 2'
  spec.add_runtime_dependency 'oga', '~> 2'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'identikal'
  spec.add_development_dependency 'slim'
end
