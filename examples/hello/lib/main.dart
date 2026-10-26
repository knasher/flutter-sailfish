import 'package:flutter/material.dart';
import 'package:flutter_sailfish/flutter_sailfish.dart';

// The count, shared by the page and the app's cover.
final counter = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // needed before using a channel
  // What the Sailfish home screen shows while the app is in the background,
  // with a + button that counts too.
  SailfishCover.set(
    const CounterCover(),
    actions: [
      CoverAction(icon: 'icon-cover-new', onPressed: () => counter.value++),
    ],
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Keeps content clear of the camera cut-out on Sailfish.
      builder: SailfishCutouts.builder,
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    counter.addListener(_counterChanged);
  }

  @override
  void dispose() {
    counter.removeListener(_counterChanged);
    super.dispose();
  }

  // The count can also change from the cover's + button. This call to
  // setState tells the Flutter framework to rerun the build method below so
  // that the display shows the new count.
  void _counterChanged() => setState(() {});

  void _incrementCounter() => counter.value++;

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _counterChanged method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: .center,
              children: [
                const Text('You have pushed the button this many times:'),
                Text(
                  '${counter.value}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                const TextField(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Keyboard test',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// The app's cover: drawn at the size of the app's tile on the Sailfish home
// screen (about 446x714 pixels, or 284x454 with many apps open), with room
// at the bottom for the + button.
class CounterCover extends StatelessWidget {
  const CounterCover({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.deepPurple.shade900,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        child: Column(
          children: [
            const FittedBox(
              child: Text(
                'Flutter Hello',
                style: TextStyle(color: Colors.white70, fontSize: 20),
              ),
            ),
            Expanded(
              child: FittedBox(
                child: ValueListenableBuilder<int>(
                  valueListenable: counter,
                  builder: (context, count, _) => Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
