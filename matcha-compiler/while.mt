var i = 0;
while i < 10 : i = i + 1 {
    printInt(i);
    if i >= 5 {
        leave;
    }
}