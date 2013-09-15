part of stream_ext_test;

class ConcatTests {
  void start() {
    group('concat', () {
      _concatWithNoErrors();
      _concatStream2CompletesBeforeStream1();
      _concatNotCloseOnError();
      _concatCloseOnError();
    });
  }

  void _concatWithNoErrors() {
    test('no errors', () {
      var controller1 = new StreamController.broadcast(sync : true);
      var controller2 = new StreamController.broadcast(sync : true);

      var stream1 = controller1.stream;
      var stream2 = controller2.stream;

      var list   = new List();
      var hasErr = false;
      var isDone = false;
      StreamExt.concat(stream1, stream2, sync : true)
        ..listen(list.add,
                 onError : (_) => hasErr = true,
                 onDone  : ()  => isDone = true);

      controller1.add(0);
      controller2.add(1); // ignored
      controller2.add(2); // ignored
      controller1.add(3);
      controller1.close() // now should be yielding from stream2
        .then((_) {
          controller2.add(4);
          controller2.add(5);
          controller2.close()
            .then((_) {
              expect(list.length, equals(4),       reason : "concatenated stream should contain 4 values");
              expect(list, equals([ 0, 3, 4, 5 ]), reason : "concatenated stream should contain values 0, 3, 4 and 5");

              expect(hasErr, equals(false), reason : "concatenated stream should not have received error");
              expect(isDone, equals(true),  reason : "concatenated stream should be completed");
            });
        });
    });
  }

  void _concatStream2CompletesBeforeStream1() {
    test('stream 2 completes before stream 1', () {
      var controller1 = new StreamController.broadcast(sync : true);
      var controller2 = new StreamController.broadcast(sync : true);

      var stream1 = controller1.stream;
      var stream2 = controller2.stream;

      var list   = new List();
      var hasErr = false;
      var isDone = false;
      StreamExt.concat(stream1, stream2, sync : true)
        ..listen(list.add,
                 onError : (_) => hasErr = true,
                 onDone  : ()  => isDone = true);

      controller1.add(0);
      controller2.add(1); // ignored
      controller2.add(2); // ignored
      controller1.add(3);
      controller2.close()
        .then((_) {
          controller1.add(4);
          controller1.close() // since stream 2 is already done this should close the stream straight away
            .then((_) {
              expect(list.length, equals(3),    reason : "concatenated stream should contain 3 values");
              expect(list, equals([ 0, 3, 4 ]), reason : "concatenated stream should contain values 0, 3 and 4");

              expect(hasErr, equals(false), reason : "concatenated stream should not have received error");
              expect(isDone, equals(true),  reason : "concatenated stream should be completed");
            });
        });
    });
  }

  void _concatNotCloseOnError() {
    test('not close on error', () {
      var controller1 = new StreamController.broadcast(sync : true);
      var controller2 = new StreamController.broadcast(sync : true);

      var stream1 = controller1.stream;
      var stream2 = controller2.stream;

      var list   = new List();
      var hasErr = false;
      var isDone = false;
      StreamExt.concat(stream1, stream2, sync : true)
        ..listen(list.add,
                 onError : (_) => hasErr = true,
                 onDone  : ()  => isDone = true);

      controller1.add(0);
      controller2.add(1); // ignored
      controller2.addError("failed");
      controller2.add(2); // ignored
      controller1.add(3);
      controller1.close();
      controller2.add(4);
      controller2.addError("failed");
      controller2.add(5);
      controller2.close()
        .then((_) {
          expect(list.length, equals(4),       reason : "concatenated stream should have only 4 events");
          expect(list, equals([ 0, 3, 4, 5 ]), reason : "concatenated stream should contain values 0, 3, 4 and 5");

          expect(hasErr, equals(true), reason : "concatenated stream should have received error");
          expect(isDone, equals(true), reason : "concatenated stream should be completed");
        });
    });
  }

  void _concatCloseOnError() {
    test('close on error', () {
      var controller1 = new StreamController.broadcast(sync : true);
      var controller2 = new StreamController.broadcast(sync : true);

      var stream1 = controller1.stream;
      var stream2 = controller2.stream;

      var list   = new List();
      var hasErr = false;
      var isDone = false;
      StreamExt.merge(stream1, stream2, closeOnError : true, sync : true)
        ..listen(list.add,
                 onError : (_) => hasErr = true,
                 onDone  : ()  => isDone = true);

      controller1.add(0);
      controller2.addError("failed");
      controller1.add(1);
      controller2.add(2);

      Future
        .wait([ controller1.close(), controller2.close() ])
        .then((_) {
          expect(list.length, equals(1), reason : "concatenated stream should have only one event before the error");
          expect(list[0],     equals(0), reason : "concatenated stream should contain the event value 0");

          expect(hasErr, equals(true), reason : "concatenated stream should have received error");
          expect(isDone, equals(true), reason : "concatenated stream should be completed");
        });
    });
  }
}