package hihex.aidl2sample;

import android.os.Parcel;
import android.os.Parcelable;

public final class CustomParcelable implements Parcelable {
    public int x;
    public int y;

    public static final Parcelable.Creator<CustomParcelable> CREATOR = new Parcelable.Creator<CustomParcelable>() {
        @Override
        public CustomParcelable createFromParcel(final Parcel source) {
            final CustomParcelable cp = new CustomParcelable();
            cp.readFromParcel(source);
            return cp;
        }

        @Override
        public CustomParcelable[] newArray(final int size) {
            return new CustomParcelable[size];
        }
    };

    @Override
    public int describeContents() {
        return 0;
    }

    @Override
    public void writeToParcel(final Parcel dest, final int flags) {
        dest.writeInt(x);
        dest.writeInt(y);
    }

    public void readFromParcel(final Parcel src) {
        x = src.readInt();
        y = src.readInt();
    }

    public static final class InnerParcelable implements Parcelable {
        public final float z;

        public static final Parcelable.Creator<InnerParcelable> CREATOR = new Parcelable.Creator<InnerParcelable>() {
            @Override
            public InnerParcelable createFromParcel(final Parcel source) {
                return new InnerParcelable(source.readFloat());
            }

            @Override
            public InnerParcelable[] newArray(final int size) {
                return new InnerParcelable[size];
            }
        };

        public InnerParcelable(final float z) {
            this.z = z;
        }

        @Override
        public int describeContents() {
            return 0;
        }

        @Override
        public void writeToParcel(final Parcel dest, final int flags) {
            dest.writeFloat(z);
        }
    }
}
