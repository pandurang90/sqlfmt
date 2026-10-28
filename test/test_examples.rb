require "minitest/autorun"
require_relative "../lib/sqlfmt"

# Snapshot tests: each examples/*.sql must format to examples/formatted/*.sql.
# After an intentional formatting change, review the diff and regenerate with:
#   for f in examples/*.sql; do bin/sqlfmt "$f" > "examples/formatted/$(basename $f)"; done
class TestExamples < Minitest::Test
  EXAMPLES_DIR = File.expand_path("../examples", __dir__)

  Dir[File.join(EXAMPLES_DIR, "*.sql")].sort.each do |path|
    name = File.basename(path, ".sql")

    define_method("test_example_#{name}") do
      expected = File.read(File.join(EXAMPLES_DIR, "formatted", "#{name}.sql"))
      got = SQLFmt.format(File.read(path))
      assert_equal expected, got, "examples/#{name}.sql no longer matches its snapshot"
      assert_equal got, SQLFmt.format(got), "examples/#{name}.sql is not idempotent"
    end
  end
end
