i18nUtils = require '../../lib/i18n-utils'
expect = require 'expect.js'
sinon = require 'sinon'
fs = require 'fs'
{loadFixture} = require '../helper'

describe 'i18nUtils', ->
  coffeeFile = subject = obj = _obj = _tree = prefix = tree =
  content = requireCallback = describedMethod =
  overrides = callback = callbackData = requires = null
  beforeEach ->
    coffeeFile = subject = obj = _obj = _tree = prefix = tree =
    content = requireCallback = parseFile = updateFile = callbackData = null
    prefix = -> 'lib/bundle/translations/'
    tree = -> _tree ||= loadFixture 'tree'
    obj = -> _obj ||= loadFixture 'i18n'
    coffeeFile = (filename = 'i18n-exports') -> fs.readFileSync "#{__dirname}/../fixtures/#{filename}.coffee"

  describe '::find', ->
    pathComponents = null
    beforeEach ->
      pathComponents = -> ['en', 'directives', 'sidebar']
      subject = -> i18nUtils.find obj(), pathComponents()

    it 'returns object', ->
      expect(subject()).to.eql { foo: 'Test' }

    it 'returns value', ->
      pathComponents = -> ['en', 'directives', 'sidebar', 'foo']
      expect(subject()).to.be 'Test'

    it 'returns empty object when inexistent', ->
      pathComponents = -> ['foo', 'bar', 'piyo']
      expect(subject()).to.eql {}

  describe '::toResources', ->
    beforeEach ->
      subject = -> i18nUtils.toResources obj(), prefix()

    it 'returns pair of paths and resources', ->
      expect(subject()).to.eql
        'lib/bundle/translations/en/directives/index.coffee':
          sidebar:
            foo: "Test"
        'lib/bundle/translations/en/filters/index.coffee':
          too_old:
            ago: "Ago"
        'lib/bundle/translations/en/views/index.coffee':
          login:
            user: "User"
        'lib/bundle/translations/ja/directives/index.coffee':
          sidebar:
            foo: "テスト"
        'lib/bundle/translations/ja/filters/index.coffee':
          too_old:
            ago: "顎"
        'lib/bundle/translations/ja/views/index.coffee':
          login:
            user: "ユーザー"


  describe '::getPendingResources', ->
    beforeEach ->
      subject = -> i18nUtils.getPendingResources tree(), obj(), prefix()
    it 'returns resources to create and update', ->
      expect(subject()).to.eql
        create: [
          {
            data:
              sidebar:
                foo: "テスト"
            path: "lib/bundle/translations/ja/directives/index.coffee"
          }
          {
            data:
              login:
                user: 'ユーザー'
            path: "lib/bundle/translations/ja/views/index.coffee"
          }
          {
            data:
              login:
                user: 'User'
            path: "lib/bundle/translations/en/views/index.coffee"
          }
        ]
        update: [
          {
            data:
              too_old:
                ago: "顎"
            path: "lib/bundle/translations/ja/filters/index.coffee"
            sha: "0000000000000000000000000000000000000003"
          }
          {
            data:
              sidebar:
                foo: "Test"
            path: "lib/bundle/translations/en/directives/index.coffee"
            sha: "0000000000000000000000000000000000000001"
          }
          {
            data:
              too_old:
                ago: "Ago"
            path: "lib/bundle/translations/en/filters/index.coffee"
            sha: "0000000000000000000000000000000000000002"
          }
        ]
        keep: [
          {
            path: "lib/bundle/translations/ja/errors/index.coffee"
            sha: "0000000000000000000000000000000000000004"
          }
        ]

  describe '::createFile', ->
    beforeEach ->
      requires = ->
        [
          { path: './views/sample1', key: 'sample1' }
          { path: './views/sample2', key: 'sample2' }
        ]
      obj = ->
        foo:
          bar: 1
        baz:
          qux: '2'
      subject = -> i18nUtils.createFile obj(), requires()
    it 'creates coffee file', ->
      expect(subject()).to.eql """
      "use strict"

      module.exports =
        sample2: require "./views/sample2"
        sample1: require "./views/sample1"
        foo:
          bar: 1
        baz:
          qux: "2"

      """

    describe 'when containing null value', ->
      beforeEach ->
        obj = ->
          foo:
            bar: null
          baz:
            qux: '2'
            hoge: null

      it 'rejects null', ->

        expect(subject()).to.eql """
        "use strict"

        module.exports =
          sample2: require "./views/sample2"
          sample1: require "./views/sample1"
          baz:
            qux: "2"

        """

    describe 'when containing sharp symbol', ->
      beforeEach ->
        obj = ->
          foo:
            bar: '#{foo}'

      it 'escapes sharp', ->

        expect(subject()).to.eql """
        "use strict"

        module.exports =
          sample2: require "./views/sample2"
          sample1: require "./views/sample1"
          foo:
            bar: "\\#\\{foo\\}"

        """


  describe '::parseFile', ->
    beforeEach ->
      content = -> coffeeFile()
      requireCallback = sinon.stub()
      describedMethod = (callback) ->
        i18nUtils.parseFile content(), requireCallback, callback

    describe 'callback data', ->
      beforeEach (done) ->
        subject = -> callbackData
        describedMethod (data) ->
          try
            callbackData = data
            do done
          catch e
            done e
      it 'callbacks parsed data', ->
        expect(subject()).to.eql obj()

    describe 'resolve require', ->
      call = null
      beforeEach ->
        call = null
        content = -> coffeeFile 'i18n-exports-require'
        callback = sinon.spy()
        describedMethod callback

      describe 'on first call', ->
        beforeEach ->
          call = requireCallback.getCall 0
        it 'does not call callback', ->
          subject = -> callback.called
          expect(subject()).to.be no
        it 'calls requireCallback', ->
          subject = -> requireCallback.called
          expect(subject()).to.be yes
        it 'called requireCallback once', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 1
        it 'calls requireCallback with arguments 0', ->
          subject = -> call.args[0]
          expect(subject()).to.eql 'qux'
        it 'calls requireCallback with arguments 1', ->
          subject = -> call.args[1]
          expect(subject()).to.eql './qux'
        it 'calls requireCallback with arguments 2', ->
          subject = -> typeof call.args[2]
          expect(subject()).to.eql 'function'

      describe 'on second call', ->
        beforeEach ->
          do requireCallback.getCall(0).args[2]
          call = requireCallback.getCall 1
        it 'does not call callback', ->
          subject = -> callback.called
          expect(subject()).to.be no
        it 'calls requireCallback', ->
          subject = -> requireCallback.called
          expect(subject()).to.be yes
        it 'called requireCallback once', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 2
        it 'calls requireCallback with arguments 0', ->
          subject = -> call.args[0]
          expect(subject()).to.eql 'foo'
        it 'calls requireCallback with arguments 1', ->
          subject = -> call.args[1]
          expect(subject()).to.eql './foo'
        it 'calls requireCallback with arguments 2', ->
          subject = -> typeof call.args[2]
          expect(subject()).to.eql 'function'

      describe 'on third call', ->
        beforeEach ->
          do requireCallback.getCall(0).args[2]
          do requireCallback.getCall(1).args[2]
          call = requireCallback.getCall 2
        it 'does not call callback', ->
          subject = -> callback.called
          expect(subject()).to.be no
        it 'calls requireCallback', ->
          subject = -> requireCallback.called
          expect(subject()).to.be yes
        it 'called requireCallback once', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 3
        it 'calls requireCallback with arguments 0', ->
          subject = -> call.args[0]
          expect(subject()).to.eql 'hoge'
        it 'calls requireCallback with arguments 1', ->
          subject = -> call.args[1]
          expect(subject()).to.eql './hoge'
        it 'calls requireCallback with arguments 2', ->
          subject = -> typeof call.args[2]
          expect(subject()).to.eql 'function'

      describe 'on fourth call', ->
        beforeEach ->
          do requireCallback.getCall(0).args[2]
          do requireCallback.getCall(1).args[2]
          do requireCallback.getCall(2).args[2]
          call = callback

        it 'calls callback', ->
          subject = -> callback.called
          expect(subject()).to.be yes

        it 'does not call requireCallback any more', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 3

        it 'calls callback with arguments', ->
          subject = -> callback.getCall(0).args
          expect(subject()).to.eql [bar: 1, baz: '2']

  describe '::updateFile', ->
    beforeEach ->
      content = -> coffeeFile()
      requireCallback = sinon.stub()
      overrides = -> ja: { directives: sidebar: baz: 'qux' }, foo: 123, qux: '456'
      describedMethod = (callback) ->
        i18nUtils.updateFile content(), overrides(), requireCallback, callback

    describe 'callback data', ->
      beforeEach (done) ->
        subject = -> callbackData
        describedMethod (data) ->
          try
            callbackData = data
            do done
          catch e
            done e
      it 'updates coffee file', ->
        expect(subject()).to.eql """
        "use strict"

        module.exports =
          ja:
            directives:
              sidebar:
                foo: "テスト"
                baz: "qux"
            filters:
              too_old:
                ago: "顎"
            views:
              login:
                user: "ユーザー"
          en:
            directives:
              sidebar:
                foo: "Test"
            filters:
              too_old:
                ago: "Ago"
            views:
              login:
                user: "User"
          foo: 123
          qux: "456"

        """

    describe 'resolve require', ->
      call = null
      beforeEach ->
        call = null
        content = -> coffeeFile 'i18n-exports-require'
        callback = sinon.spy()
        describedMethod callback

      describe 'on first call', ->
        beforeEach ->
          call = requireCallback.getCall 0
        it 'does not call callback', ->
          subject = -> callback.called
          expect(subject()).to.be no
        it 'calls requireCallback', ->
          subject = -> requireCallback.called
          expect(subject()).to.be yes
        it 'called requireCallback once', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 1
        it 'calls requireCallback with arguments 0', ->
          subject = -> call.args[0]
          expect(subject()).to.eql '456'
        it 'calls requireCallback with arguments 1', ->
          subject = -> call.args[1]
          expect(subject()).to.eql 'qux'
        it 'calls requireCallback with arguments 2', ->
          subject = -> call.args[2]
          expect(subject()).to.eql './qux'
        it 'calls requireCallback with arguments 3', ->
          subject = -> typeof call.args[3]
          expect(subject()).to.eql 'function'

      describe 'on second call', ->
        beforeEach ->
          do requireCallback.getCall(0).args[3]
          call = requireCallback.getCall 1
        it 'does not call callback', ->
          subject = -> callback.called
          expect(subject()).to.be no
        it 'calls requireCallback', ->
          subject = -> requireCallback.called
          expect(subject()).to.be yes
        it 'called requireCallback once', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 2
        it 'calls requireCallback with arguments 0', ->
          subject = -> call.args[0]
          expect(subject()).to.eql 123
        it 'calls requireCallback with arguments 1', ->
          subject = -> call.args[1]
          expect(subject()).to.eql 'foo'
        it 'calls requireCallback with arguments 2', ->
          subject = -> call.args[2]
          expect(subject()).to.eql './foo'
        it 'calls requireCallback with arguments 3', ->
          subject = -> typeof call.args[3]
          expect(subject()).to.eql 'function'

      describe 'on third call', ->
        beforeEach ->
          do requireCallback.getCall(0).args[3]
          do requireCallback.getCall(1).args[3]
          call = callback

        it 'calls callback', ->
          subject = -> callback.called
          expect(subject()).to.be yes

        it 'does not call requireCallback any more', ->
          subject = -> requireCallback.callCount
          expect(subject()).to.be 2

        it 'calls callback with arguments', ->
          subject = -> callback.getCall(0).args[0]
          expect(subject()).to.eql """
         "use strict"

         module.exports =
           hoge: require "./hoge"
           foo: require "./foo"
           qux: require "./qux"
           bar: 1
           baz: "2"
           ja:
             directives:
               sidebar:
                 baz: "qux"

          """


