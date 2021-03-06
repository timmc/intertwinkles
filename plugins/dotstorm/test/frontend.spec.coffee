expect     = require 'expect.js'
async      = require 'async'
_          = require 'underscore'
Browser    = require 'zombie'
mongoose   = require 'mongoose'
fs         = require 'fs'

common     = require '../../../test/common'
config     = require '../../../test/test_config'

schema      = require('../lib/schema').load(config)
www_schema  = require('../../../lib/schema').load(config)
api_methods = require('../../../lib/api_methods')(config)
log4js = require("log4js")
log4js.getLogger("socket_server").setLevel(log4js.levels.FATAL)

#
# Test CRUD for ideas and dotstorms for the whole socket pipeline.
#

await = (fn) ->
  if fn() == true
    return
  setTimeout (-> await fn), 100

describe "Dotstorm socket pipeline", ->
  this.timeout(20000)
  before (done) ->
    common.startUp (server) =>
      @server = server
      @browser = common.fetchBrowser()
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "visits the front page", (done) ->
    @browser.visit config.apps.dotstorm.url + "/", (blank, browser, status, errors) =>
      await =>
        if @browser.querySelector(".new-dotstorm")?
          @browser.clickLink("New dotstorm")
          await =>
            if @browser.querySelector("#add")?
              done()
              return true
          return true
  
  it "connects to a room", (done) ->
    @browser.fill("#id_slug", "test").pressButton "Create dotstorm", =>
      await =>
        if @browser.evaluate("window.location.pathname") == "/dotstorm/d/test/"
          schema.Dotstorm.findOne {slug: "test"}, (err, doc) ->
            expect(err).to.be(null)
            expect(doc).to.not.be(null)
            expect(doc.url).to.be("/d/test/")
            expect(doc.absolute_url).to.be(config.apps.dotstorm.url + "/d/test/")
            expect(doc.slug).to.be("test")
            www_schema.Event.find {entity: doc._id}, (err, events) ->
              expect(events.length).to.be(1)
              expect(events[0].type).to.be("create")
              expect(events[0].url).to.be(doc.url)
              expect(events[0].absolute_url).to.be(doc.absolute_url)
              terms = api_methods.get_event_grammar(events[0])
              expect(terms.length).to.be(1)
              expect(terms[0]).to.eql({
                entity: "Dotstorm"
                aspect: "\"Untitled\""
                collective: "created dotstorms"
                verbed: "created"
                manner: ""
              })
              # Clear events for de-comlecting of tests
              async.map(events, ((e, done) -> e.remove(done)), done)
          return true

  it "creates an idea", (done) ->
    @dotstorm_id = @browser.evaluate("ds.app.dotstorm.id")
    expect(@dotstorm_id).to.not.be undefined
    @browser.evaluate("intertwinkles.socket.send('dotstorm/create_idea', {
      dotstorm: { _id: '#{@dotstorm_id}' },
      idea: {
        description: 'first run',
        drawing: [['pencil', 0, 0, 640, 640]],
        background: '#ff9033'
      }
    });
    ds.app.ideas.once('add', function(idea) { window.testIdea = idea });")
    await =>
      backboneIdea = @browser.evaluate("window.testIdea")
      if backboneIdea != undefined
        schema.Idea.findOne {_id: backboneIdea.id}, (err, doc) =>
          @idea = doc
          expect("" + doc.dotstorm_id).to.eql @dotstorm_id
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(doc.background).to.be '#ff9033'
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            expect(events[0].url).to.be("/d/test/")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "a note"
              collective: "added notes"
              verbed: "added"
              manner: "first run"
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "updates an idea", (done) ->
    @browser.evaluate("intertwinkles.socket.send('dotstorm/edit_idea', {
        idea: {_id: testIdea.id, description: 'updated'}
      });
      testIdea.once('change', function() {
        window.ideaUpdateSuccess = true;
      });
    ")
    await =>
      if @browser.evaluate("window.ideaUpdateSuccess")
        startingVersion = @idea.imageVersion
        schema.Idea.findOne {_id: @idea._id}, (err, doc) =>
          @idea = doc
          expect(doc.description).to.be 'updated'
          expect(fs.existsSync @idea.getDrawingPath('small')).to.be true
          expect(parseInt(@idea.imageVersion) > startingVersion).to.be true
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            expect(events[0].url).to.be("/d/test/")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "a note"
              collective: "edited notes"
              verbed: "edited"
              manner: ""
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "uploads a photo", (done) ->
    @browser.evaluate("intertwinkles.socket.send('dotstorm/edit_idea', {idea: {
          _id: '#{@idea._id}',
          photoData: '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAYEBAQFBAYFBQYJBgUGCQsIBgYICwwKCgsKCgwQDAwMDAwMEAwODxAPDgwTExQUExMcGxsbHCAgICAgICAgICD/2wBDAQcHBw0MDRgQEBgaFREVGiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICD/wAARCAFKABsDAREAAhEBAxEB/8QAGQABAQEBAQEAAAAAAAAAAAAAAAECBAMI/8QAFxABAQEBAAAAAAAAAAAAAAAAABESE//EABQBAQAAAAAAAAAAAAAAAAAAAAD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwD6pAAAAAAABAAAASgUCgUEAAABAAAASgUCgUAAAAGQAAAKBQKBQQAAAEAAABAAAASgUCgUEAAABAAAASgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFAAAABkAAACgUCgUEAAABAAAAQAAAEoFAoFBAAAAQAAAEoFAoFBAAAAQAAAEAAAB47A2BsDYOboB0A6AdAc3QDoB0A6A5tgbA2BsGQAAAf/Z'
        }});
        ds.app.ideas.get('#{@idea._id}').once('change', function(idea) {
          window.ideaWithPhoto = idea;
        });
      ")
    await =>
      model = @browser.evaluate("window.ideaWithPhoto")
      if model?
        schema.Idea.findOne {_id: @idea.id}, (err, doc) =>
          expect(fs.existsSync doc.getPhotoPath('small')).to.be true
          expect(doc.photoVersion > 0).to.be true
          expect(doc.photoData).to.be undefined
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            expect(events[0].url).to.be("/d/test/")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "a note"
              collective: "edited notes"
              verbed: "edited"
              manner: ""
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true
      
  it "saves tags", (done) ->
    @browser.evaluate("
      intertwinkles.socket.send('dotstorm/edit_idea', {
        idea: {_id: '#{@idea.id}', tags: ['one', 'two', 'three']}
      });
      ds.app.ideas.get('#{@idea.id}').on('change', function(model) {
        window.taggedModel = model;
      });
    ")
    await =>
      model = @browser.evaluate("window.taggedModel")
      if model?
        expect(model.get("tags")).to.eql ["one", "two", "three"]
        schema.Idea.findOne {_id: @idea.id}, (err, doc) =>
          expect(_.isEqual doc.tags, ["one", "two", "three"]).to.be true
          www_schema.Event.find {entity: doc.dotstorm_id}, (err, events) ->
            expect(events.length).to.be(1)
            expect(events[0].type).to.be("append")
            expect(events[0].url).to.be("/d/test/")
            terms = api_methods.get_event_grammar(events[0])
            expect(terms.length).to.be(1)
            expect(terms[0]).to.eql({
              entity: "Untitled"
              aspect: "a note"
              collective: "edited notes"
              verbed: "edited"
              manner: ""
              image: doc.drawingURLs.small
            })
            # Clear events for de-comlecting of tests
            async.map(events, ((e, done) -> e.remove(done)), done)
        return true

  it "reads an idea", (done) ->
    @browser.evaluate("
      intertwinkles.socket.send('dotstorm/get_idea', {
        idea: {_id: '#{@idea._id}'}
      });
      ds.app.ideas.on('load', function() {
        window.ideaReadSuccess = true;
      });")
    await =>
      if @browser.evaluate("window.ideaReadSuccess")
        done()
        return true

  it "reads a non-existent idea", (done) ->
    # Use the dotstorm_id as a stand-in for a valid objectID which non-existent
    # doesn't exist as an idea._id
    @browser.evaluate("
      intertwinkles.socket.send('dotstorm/get_idea', {
        idea: {_id: '#{@idea.dotstorm_id}'}
      });
      intertwinkles.socket.once('error', function() {
        window.ideaReadNoExist = true;
      });")
    await =>
      nonexistent = @browser.evaluate("window.ideaReadNoExist")
      if nonexistent?
        done()
        return true

  it "creates a dotstorm", (done) ->
    @browser.evaluate("
      intertwinkles.socket.send('dotstorm/create_dotstorm', {
        dotstorm: {slug: 'crazyslug'}
      });
      ds.app.dotstorm.on('load', function(model) {
        window.createdDotstorm = model;
      });
    ")
    await =>
      dotstorm = @browser.evaluate("window.createdDotstorm")
      if dotstorm?
        expect(dotstorm.get "slug").to.be 'crazyslug'
        www_schema.Event.find {entity: dotstorm.id}, (err, events) ->
          expect(events.length).to.be(1)
          expect(events[0].type).to.be("create")
          expect(events[0].data.entity_name).to.be("Untitled")
          # Clear events for de-comlecting of tests
          async.map(events, ((e, done) -> e.remove(done)), done)
        return true
