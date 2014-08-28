#!/usr/local/bin/ruby -rubygems
#
# A simple [Pastie](http://pastie.org)-like app inspired by Nick Plante's
# [toopaste](https://github.com/zapnap/toopaste) project showing how to use
# **RethinkDB as a backend for Sinatra applications**.


require 'sinatra'
require 'rethinkdb'

#### Connection details

# We will use these settings later in the code to connect
# to the RethinkDB server.
if ENV['VCAP_SERVICES']
  services = JSON.parse(ENV['VCAP_SERVICES'])
  if service = services["rethinkdb"].first
    creds = service["credentials"]
    rdb_config ||= {
      :host => creds["hostname"],
      :port => creds["port"],
      :db   => creds["name"] || 'repasties'
    }
  end
end

rdb_config ||= {
  :host => ENV['RDB_HOST'] || 'localhost',
  :port => ENV['RDB_PORT'] || 28015,
  :db   => ENV['RDB_DB']   || 'repasties'
}

# A friendly shortcut for accessing ReQL functions
r = RethinkDB::RQL.new

#### Setting up the database

# The app will use a table `snippets` in the database defined by the
# environment variable `RDB_DB` (defaults to `repasties`).
#
# We'll create the database and the table here using
# [`db_create`](http://www.rethinkdb.com/api/ruby/db_create/)
# and
# [`table_create`](http://www.rethinkdb.com/api/ruby/table_create/) commands.
configure do
  set :db, rdb_config[:db]
  begin
    connection = r.connect(:host => rdb_config[:host],
      :port => rdb_config[:port])
  rescue Exception => err
    puts "Cannot connect to RethinkDB database #{rdb_config[:host]}:#{rdb_config[:port]} (#{err.message})"
    Process.exit(1)
  end

  begin
    r.db_create(rdb_config[:db]).run(connection)
  rescue RethinkDB::RqlRuntimeError => err
    puts "Database `repasties` already exists."
  end

  begin
    r.db(rdb_config[:db]).table_create('snippets').run(connection)
  rescue RethinkDB::RqlRuntimeError => err
    puts "Table `snippets` already exists."
  ensure
    connection.close
  end
end


#### Managing connections


# The pattern we're using for managing database connections is to have
# **a connection per request**.  We're using Sinatra's `before` and `after` for
# [opening a database connection](http://www.rethinkdb.com/api/ruby/connect/) and
# [closing it](http://www.rethinkdb.com/api/ruby/close/) respectively.
before do
  begin
    # When opening a connection we can also specify the database:
    @rdb_connection = r.connect(:host => rdb_config[:host], :port =>
      rdb_config[:port], :db => settings.db)
  rescue Exception => err
    logger.error "Cannot connect to RethinkDB database #{rdb_config[:host]}:#{rdb_config[:port]} (#{err.message})"
    halt 501, 'This page could look nicer, unfortunately the error is the same: database not available.'
  end
end

# After each request we [close the database connection](http://www.rethinkdb.com/api/ruby/close/).
after do
  begin
    @rdb_connection.close if @rdb_connection
  rescue
    logger.warn "Couldn't close connection"
  end
end

get '/' do
  @snippet = {}
  erb :new
end


# We create a new snippet in response to a POST request using
# [`table.insert`](http://www.rethinkdb.com/api/ruby/insert/).
post '/' do
  @snippet = {
    :title => params[:snippet_title],
    :body  => params[:snippet_body],
    :lang  => (params[:snippet_lang] || 'text').downcase,
  }
  if @snippet[:body].empty?
    erb :new
  end

  if @snippet[:title].empty?
    @snippet[:title] = @snippet[:body].scan(/\w+/)[0..2].join(' ')
    erb :new
  end

  @snippet[:created_at] = Time.now.to_i
  @snippet[:formatted_body] = pygmentize(@snippet[:body], @snippet[:lang])

  result = r.table('snippets').insert(@snippet).run(@rdb_connection)

  # The `insert` operation returns a single object specifying the number
  # of successfully created objects and their corresponding IDs.
  #
  # ```
  # {
  #   "inserted": 1,
  #   "errors": 0,
  #   "generated_keys": [
  #     "fcb17a43-cda2-49f3-98ee-1efc1ac5631d"
  #   ]
  # }
  # ```
  if result['inserted'] == 1
    redirect "/#{result['generated_keys'][0]}"
  else
    logger.error result
    redirect '/'
  end
end

# Every new snippet automatically gets assigned a unique ID. The browser can
# retrieve a specific snippet by GETing `/<snippet_id>`. To query the database
# for a single document by its ID, we use the
# [`get`](http://www.rethinkdb.com/api/ruby/get/) command.
get '/:id' do
  @snippet = r.table('snippets').get(params[:id]).run(@rdb_connection)

  if @snippet
    @snippet['created_at'] = Time.at(@snippet['created_at'])
    erb :show
  else
    redirect '/'
  end
end

# Retrieving the latest `max_results` (default 10) snippets by their language
# by chaining together [`filter`](http://www.rethinkdb.com/api/ruby/filter/),
# [`pluck`](http://www.rethinkdb.com/api/ruby/pluck/), and
# [`order_by`](http://www.rethinkdb.com/api/ruby/order_by/).
# All chained operations are executed on the database server and the results are
# returned as a batched iterator.
get '/lang/:lang' do
  @lang = params[:lang].downcase
  max_results = params[:limit] || 10
  results = r.table('snippets').
              filter('lang' => @lang).
              pluck('id', 'title', 'created_at').
              order_by(r.desc('created_at')).
              limit(max_results).
              run(@rdb_connection)

  @snippets = results.to_a
  @snippets.each { |s| s['created_at'] = Time.at(s['created_at']) }
  erb :list
end


# List of languages for which syntax highlighting is supported.
SUPPORTED_LANGUAGES = ['Ruby', 'Python', 'Javascript', 'Bash',
  'ActionScript', 'AppleScript', 'Awk', 'C', 'C++', 'Clojure',
  'CoffeeScript', 'Lisp', 'Erlang', 'Fortran', 'Groovy',
  'Haskell', 'Io', 'Java', 'Lua', 'Objective-C',
  'OCaml', 'Perl', 'Prolog', 'Scala', 'Smalltalk'].sort

# A Sinatra helper to expose the list of languages to views.
helpers do
  def languages
    SUPPORTED_LANGUAGES
  end
end

# Code is run through [Pygments](http://pygments.org/) for syntax
# highlighting. If it's not installed, locally, use a webservice
# http://pygments.appspot.com/.
# (code inspired by [rocco.rb](http://rtomayko.github.com/rocco/))
unless ENV['PATH'].split(':').any? { |dir|
    File.executable?("#{dir}/pygmentize") }
  warn "WARNING: Pygments not found. Using webservice."
  PYGMENTIZE=false
else
  PYGMENTIZE=true
end


def pygmentize(code, lang)
  if lang.eql? 'text'
    return code
  end
  lang.downcase!
  if PYGMENTIZE
    highlight_pygmentize(code, lang)
  else
    highlight_webservice(code, lang)
  end
end

def highlight_pygmentize(code, lang)
  code_html = nil
  open("|pygmentize -l #{lang} -f html -O encoding=utf-8,style=colorful,linenos=1",
    'r+') do |fd|
    pid =
      fork {
        fd.close_read
        fd.write code
        fd.close_write
        exit!
      }
    fd.close_write
    code_html = fd.read
    fd.close_read
    Process.wait(pid)
  end

  code_html
end

require 'net/http'

def highlight_webservice(code, lang)
  url = URI.parse 'http://pygments.appspot.com/'
  options = {'lang' => lang, 'code' => code}
  Net::HTTP.post_form(url, options).body
end

# ### Best practices ###
#
# #### Managing connections: a connection per request ####
#
# The RethinkDB server doesn't use a thread-per-connnection approach
# so opening connections per request will not slow down your database.
#
# #### Fetching multiple rows: batched iterators ####
#
# When fetching multiple rows from a table, RethinkDB returns a
# batched iterator initially containing a subset of the complete
# result. Once the end of the current batch is reached, a new batch is
# automatically retrieved from the server. From a coding point of view
# this is transparent:
#
#     r.table('todos').run(g.rdb_conn).each do |result|
#         print result
#     end
#

#### Credit

# * This sample app was inspired by Nick Plante's [toopaste](https://github.com/zapnap/toopaste) project.
# * The snippets of code used for syntax highlighting are from Ryan Tomayko's [rocco.rb](https://github.com/rtomayko/rocco) project.
# * Snippets code highlighting is done using [Pygments](http://pygments.org) or the [Pygments web service](http://pygments.appspot.com/)
# * The [Solarized dark Pygments stylesheet](https://gist.github.com/1573884) was created by Zameer Manji

#### License

# This demo application is licensed under the MIT license: <http://opensource.org/licenses/mit-license.php>
