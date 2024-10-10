interface MovingAverage<>{
   command void insert(uint16_t input);
   command command uint16_t getAverage();
}