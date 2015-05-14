describe "RallyMetrics.CorsBatchSender", ->
  Util = RallyMetrics.Util

  helpers
    createSender: (config={}) ->
      new RallyMetrics.CorsBatchSender _.defaults(config, beaconUrl: 'totallyfakeurl')

    getData: (count) ->
      ({foo: i} for i in [0...count])

    getSentData: (callIndex=0) ->
      sentJson = @mockXhr.send.args[callIndex][0]
      return JSON.parse(sentJson)

  beforeEach ->
    @mockXhr =
      send: @stub()
    @stub(Util, 'createCorsXhr').returns(@mockXhr)

  describe 'config options', ->
    describe 'min and max number of events', ->
      it 'should set the min number to 25', ->
        sender = @createSender()
        expect(sender.minNumberOfEvents).to.eql(25)

      it 'should set the max number of events to 100', ->
        sender = @createSender()
        expect(sender.maxNumberOfEvents).to.eql(100)

    describe 'keysToIgnore', ->
      it "should strip out all keys in keysToIgnore", (done) ->
        aKeyToIgnore = "testKey"
        anotherKeyToIgnore = "theOtherKey"

        sender = @createSender
          keysToIgnore: [aKeyToIgnore, anotherKeyToIgnore]
          minNumberOfEvents: 0

        data = foo: "bar"
        data[aKeyToIgnore] = "should ignore this one"
        data[anotherKeyToIgnore] = "this one too"

        @mockXhr.send = (data) =>
          sentData = JSON.parse(data)
          expect(Object.keys(sentData).length).to.eql(1)
          expect(sentData["foo.0"]).to.eql("bar")
          expect(sentData["#{aKeyToIgnore}.0"]).to.be.undefined
          expect(sentData["#{anotherKeyToIgnore}.0"]).to.be.undefined
          done()

        sender.send(data)

  describe '#send', ->
    it "should append indices to the keys so they don't get clobbered", (done) ->
      data = @getData(10)
      sender = @createSender(minNumberOfEvents: 10)

      @mockXhr.send = (dataString) =>
        sentData = JSON.parse dataString
        for d, i in sentData
          expect(sentData["foo.#{i}"]).to.equal("#{i}")
        done()

      sender.send(datum) for datum in data

    it "should not send a batch if the number of events is less than the minium", ->
      sender = @createSender
        minNumberOfEvents: 1000

      data = @getData(2)

      sender.send(datum) for datum in data
      expect(sender.getPendingEvents()).to.eql(data)
      expect(Util.createCorsXhr).not.to.have.been.called

    it "should send to the configured url", ->
      clientMetricsUrl = "http://localhost/testing"

      sender = @createSender(beaconUrl: clientMetricsUrl, minNumberOfEvents: 2)
      data = @getData(2)

      sender.send(datum) for datum in data
      expect(Util.createCorsXhr.args[0][0]).to.eql("POST")
      expect(Util.createCorsXhr.args[0][1]).to.eql(clientMetricsUrl)

    it "should disable sending client metrics if configured", ->
      sender = @createSender(disableSending: true, minNumberOfEvents: 0)
      expect(sender.isDisabled()).to.be.true
      sender.send({})
      expect(Util.createCorsXhr).not.to.have.been.called

    it "should not make a request if disabled, but still purge events", ->
      sender = @createSender(disableSending: true, minNumberOfEvents: 0)
      data = @getData(1)
      sender.send datum for datum in data

      expect(Util.createCorsXhr).not.to.have.been.called
      expect(sender._eventQueue.length).to.eql(0)

    describe "when an error occurs", ->
      it "should disable sending client metrics if there is a POST error", ->
        clientMetricsUrl = "http://unknownhost/to/force/an/error"

        sender = @createSender(beaconUrl: clientMetricsUrl, minNumberOfEvents: 0)
        sender.send({})

        expect(@mockXhr.onerror).to.be.a("function")
        expect(sender.isDisabled()).to.be.false
        @mockXhr.onerror()
        expect(sender.isDisabled()).to.be.true

      it "should disable client metrics if an exception is thrown", ->
        Util.createCorsXhr.throws()

        sender = @createSender(minNumberOfEvents: 0)
        data = @getData(1)
        sender.send datum for datum in data

        expect(sender.isDisabled()).to.be.true

  describe '#flush', ->

    it "should send a batch even though the number of events is less than the minimum", ->
      clientMetricsUrl = "http://localhost/testing"

      sender = @createSender
        beaconUrl: clientMetricsUrl
        minNumberOfEvents: 1000

      data = @getData(2)
      sender.send(datum) for datum in data

      expect(sender.getPendingEvents()).to.eql(data)
      expect(Util.createCorsXhr).not.to.have.been.called

      sender.flush()

      expect(sender.getPendingEvents().length).to.eql(0)
      expect(Util.createCorsXhr).to.have.been.calledOnce
