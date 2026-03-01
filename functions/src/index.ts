import * as admin from "firebase-admin";
import { onBlockWrite } from "./overlap";
import { onOverlapWrite } from "./notifications";

admin.initializeApp();

export { onBlockWrite, onOverlapWrite };
