describe "RallyMetrics.BatchSender", ->

  fakeBeaconUrl = 'totallyfakeurl'

  helpers
    createSender: (config={}) ->
      new RallyMetrics.BatchSender _.defaults(config, beaconUrl: fakeBeaconUrl)

    getData: (count) ->
      ({foo: i} for i in [0...count])

  beforeEach ->
    @spy document.body, 'appendChild'

  describe 'config options', ->
    describe 'min and max length', ->
      it 'should set the min length to 1700', ->
        sender = @createSender()
        expect(sender.minLength).to.eql(1700)

      it 'should set the max length to 2000', ->
        sender = @createSender()
        expect(sender.maxLength).to.eql(2000)

    describe 'keysToIgnore', ->
      it "should strip out all keys in keysToIgnore", ->
        aKeyToIgnore = "testKey"
        anotherKeyToIgnore = "theOtherKey"

        sender = @createSender
          keysToIgnore: [aKeyToIgnore, anotherKeyToIgnore]
          minLength: 0

        data = foo: "bar"
        data[aKeyToIgnore] = "should ignore this one"
        data[anotherKeyToIgnore] = "this one too"

        sender.send data

        img = document.body.appendChild.args[0][0]
        expect(img.src).to.have.string "foo.0=bar"
        expect(img.src).not.to.have.string "#{aKeyToIgnore}.0"
        expect(img.src).not.to.have.string "#{anotherKeyToIgnore}.0"

      it "should default emitWarnings to false", ->
        sender = @createSender()

        expect(sender.emitWarnings).to.be.false

  describe '#send', ->
    it "should append indices to the keys so they don't get clobbered", ->
      data = @getData(10)
      sender = @createSender(minLength: 10 * 8 + fakeBeaconUrl.length)

      sender.send datum for datum in data

      img = document.body.appendChild.args[0][0]
      for d, i in data
        expect(img.src).to.have.string "foo.#{i}=#{i}"

    it "should not send a batch if the url length is shorter than the configured min length", ->
      sender = @createSender
        minLength: 1000

      data = @getData(2)

      sender.send datum for datum in data
      expect(sender.getPendingEvents()).to.eql data
      expect(document.body.appendChild).not.to.have.been.called

    it "should not send a batch that contains one event that is too big", ->
      sender = @createSender
        minLength: 0
        maxLength: 100

      longValue = ''
      for i in [0..101]
        longValue += 'a'

      data = foo: longValue

      sender.send data

      expect(sender.getPendingEvents()).to.eql [data]
      expect(document.body.appendChild).not.to.have.been.called

    it "should send to the configured url", ->
      clientMetricsUrl = "http://localhost/testing"

      sender = @createSender(beaconUrl: clientMetricsUrl, minLength: 2 * 8 + clientMetricsUrl.length)
      data = @getData(2)

      sender.send datum for datum in data

      img = document.body.appendChild.args[0][0]
      expect(img.src).to.equal "#{clientMetricsUrl}?foo.0=0&foo.1=1"

    describe "when an error occurs", ->
      it "should disable sending client metrics if there is an img error", (done) ->
        clientMetricsUrl = "http://unknownhost/to/force/an/error"

        sender = @createSender(beaconUrl: clientMetricsUrl, minLength: 0)
        data = @getData(1)

        sender.send datum for datum in data

        checkForDisabled = ->
          if sender._disabled
            done()
          else
            # mocha will timeout after 2 seconds, causing the test to fail
            setTimeout(checkForDisabled, 10)

        checkForDisabled()

      it "should not create an img if disabled, but still purge events", ->
        sender = @createSender(minLength: 0)
        sender._disabled = true
        data = @getData(1)
        sender.send datum for datum in data

        expect(document.body.appendChild).not.to.have.been.called
        expect(sender._eventQueue.length).to.eql(0)

    describe "emitWarnings", ->
      beforeEach ->
        @stub(console, 'warn')
        @bigEvent =
          bigdata: new Array(300).join('a')

      it "should log a warning if emitWarnings is enabled and the event is too big", ->
        sender = @createSender
          minLength: 0
          maxLength: 100
          emitWarnings: true

        sender.send(@bigEvent)
        expect(console.warn).to.have.been.called

      it "should not log a warning if emitWarnings is disabled and the event is too big", ->
        sender = @createSender
          minLength: 0
          maxLength: 100
          emitWarnings: false

        sender.send(@bigEvent)
        expect(console.warn).not.to.have.been.called

  describe '#flush', ->

    it "should send a batch even though the url length is shorter than the configured min length", ->
      clientMetricsUrl = "http://localhost/testing"

      sender = @createSender
        beaconUrl: clientMetricsUrl
        minLength: 1000

      data = @getData(2)

      sender.send datum for datum in data
      expect(sender.getPendingEvents()).to.eql data
      expect(document.body.appendChild).not.to.have.been.called

      sender.flush()

      expect(sender.getPendingEvents().length).to.equal 0
      expect(document.body.appendChild).to.have.been.calledOnce
      img = document.body.appendChild.args[0][0]
      expect(img.src).to.equal "#{clientMetricsUrl}?foo.0=0&foo.1=1"
