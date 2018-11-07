test("type_coercions", function() {
  print("from js", true, 9);
});

test("nested", function() {
  print(asd.nested("12345"));
});

test("array", function() {
  var arr = getArr();
  assert(arr[0] == 9, "arr0");
  assert(arr[1] == 10, "arr1");
});

test("namespace", function() {
  assert(tester.getArr()[0] == 9, "get getArr");
});
