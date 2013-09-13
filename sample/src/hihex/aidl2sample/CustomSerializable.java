package hihex.aidl2sample;

import java.io.Serializable;

public final class CustomSerializable implements Serializable {
    private static final long serialVersionUID = 3675076713410123453L;

    public int foo;
    public int bar;
    public int baz;

    public CustomSerializable(final int foo, final int bar, final int baz) {
        this.foo = foo;
        this.bar = bar;
        this.baz = baz;
    }
}
