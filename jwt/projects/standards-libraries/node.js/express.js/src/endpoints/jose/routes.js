import {Router} from "express"
import { Index } from "./controller.js"

const router = Router()

router.get('/', Index)

export default router