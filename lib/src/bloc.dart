import 'dart:async';

import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

typedef StateProvider<T> = T Function();

abstract class Bloc<S> {
  S currentState();

  Stream<S> state();

  void release();
}

abstract class MutableBloc<S> implements Bloc<S> {
  void add(Event<S> event);
}

abstract class ErrorProneState<S extends ErrorProneState<S>> {
  Object? get error;

  S clearError();
}

extension ErrorProneStateErrorCheck on ErrorProneState {
  bool get hasError => error != null;
}

abstract class Event<S> {
  Stream<S> fold(StateProvider<S> currentState);
}

@immutable
class ErrorProcessedEvent<S extends ErrorProneState<S>> implements Event<S> {
  const ErrorProcessedEvent();

  @override
  Stream<S> fold(StateProvider<S> currentState) =>
      Stream.value(currentState().clearError());
}

class StreamTransformerBloc<S> implements MutableBloc<S> {
  StreamTransformerBloc(
    TransformerFactory<Event<S>, S> factory, {
    required S initialState,
    Event<S>? initialEvent,
  }) {
    _stateSubject.add(initialState);
    if (initialEvent != null) add(initialEvent);
    _eventSC.stream
        .transform(factory.transform(_fold))
        .listen(_stateSubject.add);
  }

  StreamTransformerBloc.electLast({
    required S initialState,
    Event<S>? initialEvent,
  }) : this(SwitchMapTransformerFactory(),
            initialState: initialState, initialEvent: initialEvent);

  StreamTransformerBloc.mix({
    required S initialState,
    Event<S>? initialEvent,
  }) : this(FlatMapTransformerFactory(),
            initialState: initialState, initialEvent: initialEvent);

  StreamTransformerBloc.ordered({
    required S initialState,
    Event<S>? initialEvent,
  }) : this(ConcatMapTransformerFactory(),
            initialState: initialState, initialEvent: initialEvent);

  Stream<S> _fold(Event<S> event) => event.fold(currentState);

  @override
  void add(Event<S> event) => _eventSC.add(event);

  @override
  S currentState() => _stateSubject.value!;

  @override
  Stream<S> state() => _stateSubject;

  @override
  void release() {
    _stateSubject.close();
    _eventSC.close();
  }

  final _stateSubject = BehaviorSubject<S>();

  final _eventSC = StreamController<Event<S>>();
}

abstract class TransformerFactory<T, S> {
  StreamTransformer<T, S> transform(Stream<S> Function(T) map);
}

class SwitchMapTransformerFactory<T, S> implements TransformerFactory<T, S> {
  @override
  StreamTransformer<T, S> transform(Stream<S> Function(T) map) =>
      SwitchMapStreamTransformer(map);
}

class FlatMapTransformerFactory<T, S> implements TransformerFactory<T, S> {
  @override
  StreamTransformer<T, S> transform(Stream<S> Function(T) map) =>
      FlatMapStreamTransformer(map);
}

class ConcatMapTransformerFactory<T, S> implements TransformerFactory<T, S> {
  @override
  StreamTransformer<T, S> transform(Stream<S> Function(T) map) =>
      _AsyncExpandTransformer(map);
}

class _AsyncExpandTransformer<T, S> extends StreamTransformerBase<T, S> {
  _AsyncExpandTransformer(this.map);

  @override
  Stream<S> bind(Stream<T> stream) => stream.asyncExpand(map);

  final Stream<S> Function(T event) map;
}
