library stream_ext;

import 'dart:async';

class StreamExt {
  static _getOnErrorHandler(StreamController controller, closeOnError) {
      return closeOnError
              ? (err) {
                controller.addError(err);
                controller.close();
              }
              : controller.addError;
  }

  static _tryClose(StreamController controller) {
    if (!controller.isClosed) controller.close();
  }

  static _tryAdd(StreamController controller, event) {
    if (!controller.isClosed) controller.add(event);
  }

  /// Merges two stream into one, the merged stream will forward any events and errors received from the input
  /// streams. The merged stream will complete if:
  /// * both input streams have completed
  /// * [closeOnError] flag is set to true and an error is received
  static Stream merge(Stream stream1, Stream stream2, { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var completer1 = new Completer();
    var completer2 = new Completer();
    var onError    = _getOnErrorHandler(controller, closeOnError);

    stream1.listen((x) => _tryAdd(controller, x),
                   onError : onError,
                   onDone  : completer1.complete);
    stream2.listen((x) => _tryAdd(controller, x),
                   onError : onError,
                   onDone  : completer2.complete);

    Future
      .wait([ completer1.future, completer2.future ])
      .then((_) => _tryClose(controller));

    return controller.stream;
  }

  /// Merges two streams into one stream by using the selector function whenever one of the streams produces an event.
  /// The merged stream will complete if:
  /// * both input streams have completed
  /// * [closeOnError] flag is set to true and an error is received
  static Stream combineLatest(Stream stream1, Stream stream2, dynamic selector(dynamic item1, dynamic item2), { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var completer1 = new Completer();
    var completer2 = new Completer();
    var onError    = _getOnErrorHandler(controller, closeOnError);

    // current latest items on each stream
    var item1;
    var item2;

    void handleNewEvent() {
      if (item1 != null && item2 != null) {
        _tryAdd(controller, selector(item1, item2));
      }
    }

    stream1.listen((x) {
        item1 = x;
        handleNewEvent();
      },
      onError : onError,
      onDone  : completer1.complete);
    stream2.listen((x) {
        item2 = x;
        handleNewEvent();
      },
      onError : onError,
      onDone  : completer2.complete);

    Future
      .wait([ completer1.future, completer2.future ])
      .then((_) => _tryClose(controller));

    return controller.stream;
  }

  /// Creates a new stream whose events are sourced from the input stream but delivered after the specified duration.
  /// The delayed stream will complete if:
  /// * the input stream has completed and the delayed complete message has been delivered
  /// * [closeOnError] flag is set to true and an error is received
  static Stream delay(Stream input, Duration duration, { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var onError    = _getOnErrorHandler(controller, closeOnError);

    delayCall(f, [ x ]) => x == null ? new Timer(duration, f) : new Timer(duration, () => f(x));

    input.listen((x) => delayCall(() => _tryAdd(controller, x)),
                 onError : (err) => delayCall(onError, err),
                 onDone  : ()    => delayCall(() => _tryClose(controller)));

    return controller.stream;
  }

  /// Creates a new stream who stops the flow of events produced by the input stream until no new event has been
  /// produced by the input stream after the specified duration.
  /// The throttled stream will complete if:
  /// * the input stream has completed and the any throttled message has been delivered
  /// * [closeOnError] flag is set to true and an error is received
  static Stream throttle(Stream input, Duration duration, { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var onError    = _getOnErrorHandler(controller, closeOnError);

    var isThrottling = false;
    var buffer;
    void handleNewEvent(x) {
      // if this is the first item then push it
      if (!isThrottling) {
        _tryAdd(controller, x);
        isThrottling = true;

        new Timer(duration, () => isThrottling = false);
      } else {
        buffer = x;
        isThrottling = true;

        new Timer(duration, () {
          // when the timer callback is invoked after the timeout, check if there has been any
          // new items by comparing the last item against our captured closure 'x'
          // only push the event to the output stream if the captured event has not been
          // superceded by a subsequent event
          if (buffer == x) {
            _tryAdd(controller, x);

            // reset
            isThrottling = false;
            buffer = null;
          }
        });
      }
    }

    input.listen(handleNewEvent,
                 onError : onError,
                 onDone  : () {
                    if (isThrottling && buffer != null) {
                      _tryAdd(controller, buffer);
                    }
                    _tryClose(controller);
                  });

    return controller.stream;
  }

  /// Zips two streams into one by combining their elements in a pairwise fashion.
  /// The zipped stream will complete if:
  /// * either input stream has completed
  /// * [closeOnError] flag is set to true and an error is received
  static Stream zip(Stream stream1, Stream stream2, dynamic zipper(dynamic item1, dynamic item2), { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var onError    = _getOnErrorHandler(controller, closeOnError);

    // lists to track the data that had been buffered for the two streams
    var buffer1 = new List();
    var buffer2 = new List();

    // handler for new event being added to the list on the left
    void handleNewEvent(List left, List right, dynamic newValue) {
      left.add(newValue);

      if (right.isEmpty) {
        return;
      }

      // get and remove the first available items from the two buffers, zip them and return them
      var item1 = buffer1.removeAt(0);
      var item2 = buffer2.removeAt(0);
      _tryAdd(controller, zipper(item1, item2));
    }

    stream1.listen((x) => handleNewEvent(buffer1, buffer2, x),
                   onError : onError,
                   onDone  : () => _tryClose(controller));
    stream2.listen((x) => handleNewEvent(buffer2, buffer1, x),
                   onError : onError,
                   onDone  : () => _tryClose(controller));

    return controller.stream;
  }

  /// Projects each element from the input stream into consecutive non-overlapping windows. Each element produced by the output
  /// stream will contains a list of elements up to the specified count.
  /// The output stream will complete if:
  /// * the input stream has completed and any buffered elements have been pushed
  /// * [closeOnError] flag is set to true and an error is received
  static Stream window(Stream input, int count, { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var onError    = _getOnErrorHandler(controller, closeOnError);

    var buffer   = new List();
    void pushBuffer() {
      if (buffer.length == count) {
        _tryAdd(controller, buffer.toList()); // add a clone instead of the buffer list
        buffer.clear();
      }
    }

    void handleNewEvent(x) {
      buffer.add(x);
      pushBuffer();
    }

    input.listen(handleNewEvent,
                 onError : onError,
                 onDone  : () {
                   if (buffer.length > 0) {
                     _tryAdd(controller, buffer.toList()); // add a clone instead of the buffer list
                   }
                   _tryClose(controller);
                 });

    return controller.stream;
  }

  /// Creates a new stream which buffers elements from the input stream produced within the specified duration. Each element
  /// produced by the output stream is a list.
  /// The output stream will complete if:
  /// * the input stream has completed and any buffered elements have been pushed
  /// * [closeOnError] flag is set to true and an error is received
  static Stream buffer(Stream input, Duration duration, { bool closeOnError : false, bool sync : false }) {
    var controller = new StreamController.broadcast(sync : sync);
    var onError    = _getOnErrorHandler(controller, closeOnError);

    var buffer = new List();
    void pushBuffer() {
      if (buffer.length > 0) {
        _tryAdd(controller, buffer.toList()); // add a clone instead of the buffer list
        buffer.clear();
      }
    }

    new Timer.periodic(duration, (_) => pushBuffer());

    input.listen(buffer.add,
                 onError  : onError,
                 onDone   : () {
                   pushBuffer();
                   _tryClose(controller);
                 });

    return controller.stream;
  }
}