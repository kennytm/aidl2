package hihex.aidl2sample;

import android.os.RemoteException;

public interface Predicate {
    public boolean run() throws RemoteException;
}
