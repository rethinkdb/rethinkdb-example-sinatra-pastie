# What is it #

A simple [Pastie.org](http://pastie.org)-like web application inspired by Nick Plante's [toopaste](https://github.com/zapnap/toopaste) project
showing how to use **RethinkDB as a backend for Sinatra applications**.

The app demos the following functionality:

*   Creating a new snippet (code highlighting included)
*   Retrieving a snippet
*   Listing snippets for a language

The app could be easily extended to provide more interesting features like:

*   pagination
*   snippet expiration

Fork it and send us a pull request.

# Complete stack #

*   [Sinatra](http://www.sinatrarb.com/)
*   [RethinkDB](http://www.rethinkdb.com)

# Installation #

```
git clone git://github.com/rethinkdb/rethinkdb-example-sinatra-pastie.git
cd rethinkdb-example-sinatra-pastie
bundle
```

_Note_: If you don't have RethinkDB installed, you can follow [these instructions to get it up and running](http://www.rethinkdb.com/docs/install/).

# Running the application #

Running a Sinatra app is as easy as:

```
rackup
```

# Credits #

* This sample app was inspired by Nick Plante's [toopaste](https://github.com/zapnap/toopaste) project.
* The snippets of code used for syntax highlighting are from Ryan Tomayko's [rocco.rb](https://github.com/rtomayko/rocco) project.
* Code highlighting in snippets is done using [Pygments](http://pygments.org) or the [Pygments web service](http://pygments.appspot.com/)
* The [Solarized dark Pygments stylesheet](https://gist.github.com/1573884) was created by Zameer Manji

# License #

This demo application is licensed under the [MIT license](http://opensource.org/licenses/mit-license.php).
