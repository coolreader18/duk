function section(name, func) {
  print("\n=======  " + name + "  =======");
  try {
    func();
    pass();
  } catch (e) {
    fail();
  }
}

section("type coercions", function() {
  print("from js", true, 9);
  throw 0;
});

section("setting a", function() {
  setA(get22(), 10);
});

section("nested", function() {
  print(asd.nested("12345"));
});

section("array", function() {
  var arr = getArr();
  print(arr[0], arr[1]);
});

section("namespace", function() {
  print(tester.get22() == 22);
});
