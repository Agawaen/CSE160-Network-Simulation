generic module MovingAverage(int n){
   provides interface MovingAverage<t>;
   uses interface Queue<uint16_t>;
}

implementation{
    uint16_t period = n;
    uint16_t sum = 0;

    command void insert(uint16_t input){
        call queue.enqueue(input);
        sum += input;
        if (queue.count > period) {
            sum -= queue.dequeue();
        }
    }

    command command uint16_t getAverage(){
        return sum / period;
    }
}