class Foo {
	private int _bar = 1;
	public int bar {
		set => _bar = value;
		get => _bar;
	}

	public int baz () => 2;
	public int qux () => baz ();
}

void main () {
	var foo = new Foo ();
	assert (foo.bar == 1);
	assert (foo.baz () == 2);
	assert (foo.qux () == 2);
}
