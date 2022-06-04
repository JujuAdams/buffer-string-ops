batch = new BufferBatch();
batch.FromString("draw_text(((10)), ((20)), ((\"Hello world\")));");
//                          1111111111222222222233333333334444444
//                01234567890123456789012345678901234567890123456

batch.Insert(11, "__DynamoVariable");
batch.Delete(12, 2);
batch.Insert(12, "0x1");

batch.Insert(19, "__DynamoVariable");
batch.Delete(20, 2);
batch.Insert(20, "0x2");

batch.Insert(27, "__DynamoVariable");
batch.Delete(28, 13);
batch.Insert(28, "0x3");

/*
batch.Delete(10, 2);
batch.Delete(14, 2);
batch.Delete(18, 2);
batch.Delete(22, 2);
batch.Delete(26, 2);
batch.Delete(43, 2);
*/

outputString = batch.GetString();