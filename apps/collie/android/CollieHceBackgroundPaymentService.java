package org.flexscript.collie;

/** Payment routing still requires the user's Android wallet/default selection. */
public final class CollieHceBackgroundPaymentService extends CollieHceBackgroundService {
    int category(){return 1;}
}
